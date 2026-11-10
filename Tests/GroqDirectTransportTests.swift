import Foundation
import Network

/// Local plain-TCP HTTP/1.1 server for pool tests. No external network.
private final class LocalHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FreeFlowTests.LocalHTTPServer")
    private let lock = NSLock()
    private var accepted = 0
    private var requests: [String] = []
    private var live: [NWConnection] = []
    private var responder: @Sendable (String) -> (Data, Bool) = { _ in
        (Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".utf8), false)
    }
    /// Raw response for a request head; second value closes the connection afterwards.
    var respond: @Sendable (String) -> (Data, Bool) {
        get { lock.lock(); defer { lock.unlock() }; return responder }
        set { lock.lock(); responder = newValue; lock.unlock() }
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock()
            self.accepted += 1
            self.live.append(connection)
            self.lock.unlock()
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
        }
    }

    private var startContinuation: CheckedContinuation<UInt16, Error>?

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                self.lock.lock()
                let pending = self.startContinuation
                switch state {
                case .ready, .failed: self.startContinuation = nil
                default: break
                }
                self.lock.unlock()
                switch state {
                case .ready: pending?.resume(returning: self.listener.port!.rawValue)
                case .failed(let error): pending?.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    var acceptedConnections: Int {
        lock.lock()
        defer { lock.unlock() }
        return accepted
    }

    var receivedRequests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    /// Server-side idle close, like a provider dropping a kept-alive connection.
    func closeAllConnections() {
        lock.lock()
        let connections = live
        live.removeAll()
        lock.unlock()
        connections.forEach { $0.cancel() }
    }

    func stop() {
        closeAllConnections()
        listener.cancel()
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            while let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
                let length = head.components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                guard buffer.endIndex - end.upperBound >= length else { break }
                let body = String(decoding: buffer[end.upperBound..<(end.upperBound + length)], as: UTF8.self)
                buffer = Data(buffer[(end.upperBound + length)...])
                self.lock.lock()
                self.requests.append(head + "\r\n\r\n" + body)
                self.lock.unlock()
                let (response, close) = self.respond(head)
                connection.send(content: response, completion: .contentProcessed { _ in
                    if close { connection.cancel() }
                })
                if close { return }
            }
            if isComplete || error != nil { return }
            self.read(connection, buffer: buffer)
        }
    }
}

enum GroqDirectTransportTests {
    static func run() async {
        codecRequestTests()
        codecResponseTests()
        await poolTests()
    }

    private static func request(_ url: String, method: String = "POST", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 5)
        request.httpMethod = method
        request.httpBody = body
        return request
    }

    static func codecRequestTests() {
        var post = request("https://api.groq.com/openai/v1/audio/transcriptions?x=1%202", body: Data("abc".utf8))
        post.setValue("Bearer synthetic-token", forHTTPHeaderField: "Authorization")
        post.setValue("evil.invalid", forHTTPHeaderField: "Host")
        post.setValue("999", forHTTPHeaderField: "Content-Length")
        post.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let text = String(decoding: try! HTTP1Codec.requestData(for: post, body: nil), as: UTF8.self)
        TestSupport.expect(text.hasPrefix("POST /openai/v1/audio/transcriptions?x=1%202 HTTP/1.1\r\nHost: api.groq.com\r\n"), "Request line keeps encoded path and query and owns Host")
        TestSupport.expect(text.contains("Authorization: Bearer synthetic-token\r\n") && text.contains("Content-Length: 3\r\n") && text.hasSuffix("\r\n\r\nabc"), "Headers and body are written with the real length")
        TestSupport.expect(!text.contains("evil.invalid") && !text.contains("999") && !text.contains("gzip"), "Caller cannot override framing, Host or encoding")

        let binary = Data([0, 13, 10, 255])
        let upload = try! HTTP1Codec.requestData(for: request("https://api.groq.com/x"), body: binary)
        TestSupport.expect(upload.suffix(4) == binary && String(decoding: upload, as: UTF8.self).contains("Content-Length: 4\r\n"), "Explicit upload body wins and stays binary")

        let empty = String(decoding: try! HTTP1Codec.requestData(for: request("https://api.groq.com/x"), body: nil), as: UTF8.self)
        TestSupport.expect(empty.contains("Content-Length: 0\r\n"), "Body-less POST declares zero length")

        var injected = request("https://api.groq.com/x")
        injected.setValue("a\r\nX-Evil: 1", forHTTPHeaderField: "X-Test")
        let injectedText = (try? HTTP1Codec.requestData(for: injected, body: nil)).map { String(decoding: $0, as: UTF8.self) }
        TestSupport.expect(injectedText.map { !$0.contains("X-Evil") } ?? true, "Header injection never reaches the wire")
    }

    private static func read(_ chunks: [String], method: String = "POST", finish: Bool = false) throws -> HTTP1Codec.Response? {
        var reader = HTTP1Codec.ResponseReader(method: method)
        for chunk in chunks { try reader.consume(Data(chunk.utf8)) }
        if finish { try reader.finish() }
        return reader.response
    }

    static func codecResponseTests() {
        let split = try! read(["HTTP/1.1 200 OK\r\nContent-Le", "ngth: 5\r\nX-Request-Id: a\r\n\r\nhel", "lo"])
        TestSupport.expect(split?.statusCode == 200 && split?.body == Data("hello".utf8) && split?.reusable == true && split?.headers["X-Request-Id"] == "a", "Content-Length body across reads")

        TestSupport.expect(try! read(["HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhel"]) == nil, "Incomplete body waits for more bytes")

        let chunked = try! read(["HTTP/1.1 401 Unauthorized\r\nTransfer-Encoding: chunked\r\n\r\n4;ext=1\r\n{\"a\"\r\n", "2\r\n:1\r\n1\r\n}\r\n0\r\nX-Trailer: t\r\n\r\n"])
        TestSupport.expect(chunked?.statusCode == 401 && chunked?.body == Data("{\"a\":1}".utf8) && chunked?.reusable == true, "Chunked body with extensions and trailers")

        let continued = try! read(["HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"])
        TestSupport.expect(continued?.statusCode == 200 && continued?.body == Data("ok".utf8), "Informational response is skipped")

        let closing = try! read(["HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 2\r\n\r\nok"])
        TestSupport.expect(closing?.reusable == false, "Connection: close is not reused")

        let untilClose = try! read(["HTTP/1.1 200 OK\r\n\r\npart1", "part2"], finish: true)
        TestSupport.expect(untilClose?.body == Data("part1part2".utf8) && untilClose?.reusable == false, "Unframed body ends at close and is not reused")

        let head = try! read(["HTTP/1.1 200 OK\r\nContent-Length: 1234\r\n\r\n"], method: "HEAD")
        TestSupport.expect(head?.body.isEmpty == true && head?.reusable == true, "HEAD response has no body")

        TestSupport.expect((try? read(["HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nxx"])) == nil, "Conflicting lengths are rejected")
        TestSupport.expect((try? read(["NOTHTTP 200 OK\r\n\r\n"])) == nil, "Malformed status line is rejected")
        TestSupport.expect((try? read(["HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\nok"], finish: true)) == nil, "Truncated body is an error")
    }

    static func poolTests() async {
        let server = try! LocalHTTPServer()
        let port = try! await server.start()
        defer { server.stop() }
        let pool = GroqDirectConnectionPool(host: "127.0.0.1", port: port, usesTLS: false, bindsToPhysicalInterface: false)
        let url = "http://127.0.0.1:\(port)/openai/v1/models"

        let first = try! await pool.send(request(url, method: "GET"), body: nil)
        let second = try! await pool.send(request(url, body: Data("audio".utf8)), body: nil)
        TestSupport.expect(first.statusCode == 200 && second.body == Data("ok".utf8), "Pool returns responses")
        TestSupport.expect(server.acceptedConnections == 1 && pool.connectionsOpened == 1, "Sequential requests reuse one kept-alive connection")
        TestSupport.expect(server.receivedRequests.last?.hasSuffix("\r\n\r\naudio") == true, "Body reaches the server")

        // Server dropped the idle connection: the next request transparently uses a fresh one.
        server.closeAllConnections()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let afterClose = try! await pool.send(request(url, method: "GET"), body: nil)
        TestSupport.expect(afterClose.statusCode == 200 && server.acceptedConnections == 2, "Closed idle connection is replaced once")

        // Connection: close responses are not pooled (the first reuses the idle one).
        server.respond = { _ in (Data("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8), true) }
        _ = try! await pool.send(request(url, method: "GET"), body: nil)
        _ = try! await pool.send(request(url, method: "GET"), body: nil)
        TestSupport.expect(server.acceptedConnections == 3, "Non-reusable responses open new connections")

        // Prewarm opens the connection that the next request then uses.
        server.respond = { _ in (Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8), false) }
        let warmPool = GroqDirectConnectionPool(host: "127.0.0.1", port: port, usesTLS: false, bindsToPhysicalInterface: false)
        warmPool.prewarm()
        for _ in 0..<50 where server.acceptedConnections < 4 { try? await Task.sleep(nanoseconds: 10_000_000) }
        try? await Task.sleep(nanoseconds: 50_000_000)
        _ = try! await warmPool.send(request(url, method: "GET"), body: nil)
        TestSupport.expect(server.acceptedConnections == 4 && warmPool.connectionsOpened == 1, "Request reuses the prewarmed connection")

        // Server never answers: the request deadline wins.
        server.respond = { _ in (Data(), false) }
        var slow = request(url, method: "GET")
        slow.timeoutInterval = 0.3
        do {
            _ = try await pool.send(slow, body: nil)
            fatalError("Silent server must time out")
        } catch {
            TestSupport.expect((error as? URLError)?.code == .timedOut, "Direct request honours its deadline")
        }

        // Cancellation stops a waiting request promptly.
        let cancelled = Task { try await pool.send(request(url, method: "GET"), body: nil) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancelled direct request completed") }
        catch { TestSupport.expect(error is CancellationError, "Direct request cancellation propagates") }
    }
}
