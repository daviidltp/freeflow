import Foundation

/// Minimal HTTP/1.1 request writer and incremental response reader used by the
/// Groq direct route. It only supports what that route needs: one request per
/// connection at a time, Content-Length or chunked responses, and keep-alive.
enum HTTP1Codec {
    struct InvalidMessage: Error {}

    static let maximumResponseBytes = 32 * 1024 * 1024
    private static let maximumHeaderBytes = 64 * 1024

    /// Headers this writer owns; caller-provided copies are dropped.
    private static let managedHeaders: Set<String> = [
        "host", "content-length", "connection", "transfer-encoding", "keep-alive",
        "proxy-connection", "upgrade", "te", "expect", "accept-encoding"
    ]

    private static func isToken(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~")
            .union(CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeValue(_ value: String) -> Bool {
        !value.contains("\r") && !value.contains("\n") && !value.contains("\0")
    }

    static func requestData(for request: URLRequest, body: Data?) throws -> Data {
        guard let url = request.url, let host = url.host, !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw InvalidMessage()
        }
        let method = request.httpMethod ?? "GET"
        guard isToken(method) else { throw InvalidMessage() }
        var target = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { target += "?" + query }
        guard isSafeValue(target), !target.contains(" ") else { throw InvalidMessage() }

        var authority = host
        if let port = url.port { authority += ":\(port)" }
        var head = "\(method) \(target) HTTP/1.1\r\nHost: \(authority)\r\n"
        for (name, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard isToken(name), isSafeValue(value) else { throw InvalidMessage() }
            if managedHeaders.contains(name.lowercased()) { continue }
            head += "\(name): \(value)\r\n"
        }
        let payload = body ?? request.httpBody
        if let payload {
            head += "Content-Length: \(payload.count)\r\n"
        } else if ["POST", "PUT", "PATCH"].contains(method.uppercased()) {
            head += "Content-Length: 0\r\n"
        }
        head += "Connection: keep-alive\r\n\r\n"
        var data = Data(head.utf8)
        if let payload { data.append(payload) }
        return data
    }

    struct Response: Equatable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
        /// Whether the connection can carry another request afterwards.
        let reusable: Bool
    }

    /// Incremental response reader. Feed bytes as they arrive; `finish()`
    /// signals the peer closed the connection.
    struct ResponseReader {
        private enum Framing { case none, length(Int), chunked, untilClose }
        private enum State { case head, body(Framing), done }

        private let isHeadRequest: Bool
        private var buffer = Data()
        private var state = State.head
        private var statusCode = 0
        private var headers: [String: String] = [:]
        private var keepAlive = true
        private var body = Data()
        private(set) var response: Response?
        /// True once any byte arrived; a reused connection that dies before
        /// this is safe to retry on a fresh connection.
        private(set) var receivedAnyBytes = false

        init(method: String) {
            isHeadRequest = method.uppercased() == "HEAD"
        }

        mutating func consume(_ data: Data) throws {
            if !data.isEmpty { receivedAnyBytes = true }
            buffer.append(data)
            try advance()
        }

        mutating func finish() throws {
            if case .body(.untilClose) = state {
                complete(reusable: false)
                return
            }
            if response == nil { throw InvalidMessage() }
        }

        private mutating func complete(reusable: Bool) {
            state = .done
            response = Response(statusCode: statusCode, headers: headers, body: body, reusable: reusable && keepAlive)
        }

        private mutating func advance() throws {
            while true {
                switch state {
                case .done:
                    return
                case .head:
                    guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                        if buffer.count > HTTP1Codec.maximumHeaderBytes { throw InvalidMessage() }
                        return
                    }
                    let headData = buffer.subdata(in: buffer.startIndex..<end.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                    try parseHead(headData)
                case .body(let framing):
                    switch framing {
                    case .none:
                        complete(reusable: true)
                    case .length(let length):
                        guard buffer.count >= length else { return }
                        body = Data(buffer.prefix(length))
                        buffer.removeFirst(length)
                        complete(reusable: buffer.isEmpty)
                    case .untilClose:
                        body.append(buffer)
                        buffer.removeAll()
                        if body.count > HTTP1Codec.maximumResponseBytes { throw InvalidMessage() }
                        return
                    case .chunked:
                        guard try readChunk() else { return }
                    }
                }
            }
        }

        private mutating func parseHead(_ data: Data) throws {
            guard let text = String(data: data, encoding: .isoLatin1) else { throw InvalidMessage() }
            var lines = text.components(separatedBy: "\r\n")
            let statusLine = lines.removeFirst()
            let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."),
                  parts[1].count == 3, let code = Int(parts[1]), (100...599).contains(code) else {
                throw InvalidMessage()
            }
            var fields: [String: String] = [:]
            var lowercased: [String: String] = [:]
            for line in lines where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { throw InvalidMessage() }
                let name = String(line[..<colon])
                guard HTTP1Codec.isToken(name) else { throw InvalidMessage() }
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                let key = name.lowercased()
                if let existing = lowercased[key] {
                    // Duplicate Content-Length values must agree; anything else is ambiguous.
                    if key == "content-length", existing != value { throw InvalidMessage() }
                    lowercased[key] = existing + ", " + value
                } else {
                    lowercased[key] = value
                }
                fields[name] = lowercased[key]
            }
            // Informational responses (100 Continue, 103 Early Hints) precede the real one.
            if (100...199).contains(code) {
                guard code != 101 else { throw InvalidMessage() }
                return
            }
            statusCode = code
            headers = fields
            let connection = (lowercased["connection"] ?? "").lowercased()
            keepAlive = parts[0] == "HTTP/1.1" ? !connection.contains("close") : connection.contains("keep-alive")

            if isHeadRequest || code == 204 || code == 304 {
                state = .body(.none)
            } else if let encoding = lowercased["transfer-encoding"] {
                guard encoding.lowercased() == "chunked", lowercased["content-length"] == nil else {
                    throw InvalidMessage()
                }
                state = .body(.chunked)
            } else if let lengthText = lowercased["content-length"] {
                guard let length = Int(lengthText), length >= 0,
                      length <= HTTP1Codec.maximumResponseBytes else { throw InvalidMessage() }
                state = .body(.length(length))
            } else {
                state = .body(.untilClose)
            }
        }

        /// Returns false when more bytes are needed.
        private mutating func readChunk() throws -> Bool {
            let crlf = Data("\r\n".utf8)
            guard let lineEnd = buffer.range(of: crlf) else {
                if buffer.count > 1024 { throw InvalidMessage() }
                return false
            }
            let sizeLine = String(decoding: buffer[buffer.startIndex..<lineEnd.lowerBound], as: UTF8.self)
            let sizeText = sizeLine.split(separator: ";", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespaces)
            } ?? ""
            guard !sizeText.isEmpty, sizeText.count <= 8, let size = Int(sizeText, radix: 16), size >= 0 else {
                throw InvalidMessage()
            }
            if size == 0 {
                // Last chunk: skip optional trailers up to the blank line.
                let rest = buffer[lineEnd.upperBound...]
                if rest.starts(with: crlf) {
                    buffer.removeSubrange(buffer.startIndex..<(lineEnd.upperBound + 2))
                } else if let trailerEnd = buffer.range(of: Data("\r\n\r\n".utf8), in: lineEnd.upperBound..<buffer.endIndex) {
                    buffer.removeSubrange(buffer.startIndex..<trailerEnd.upperBound)
                } else {
                    return false
                }
                complete(reusable: buffer.isEmpty)
                return true
            }
            let dataStart = lineEnd.upperBound
            guard buffer.endIndex - dataStart >= size + 2 else { return false }
            let dataEnd = dataStart + size
            guard buffer[dataEnd..<(dataEnd + 2)].elementsEqual(crlf) else { throw InvalidMessage() }
            body.append(buffer[dataStart..<dataEnd])
            if body.count > HTTP1Codec.maximumResponseBytes { throw InvalidMessage() }
            buffer.removeSubrange(buffer.startIndex..<(dataEnd + 2))
            return true
        }
    }
}
