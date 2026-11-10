import Foundation
import Network

/// A narrowly scoped escape from Groq's VPN egress block. Groq answers requests
/// that leave through some VPNs (for example ProtonVPN) with an exact 403. Only
/// for that answer, FreeFlow repeats the request to api.groq.com over the
/// physical Wi-Fi/Ethernet interface. No global routing changes.
///
/// To keep dictation as fast as without a VPN:
/// - `GroqRouteMemory` remembers the block, so later requests go direct at once
///   instead of uploading through the VPN first just to be rejected again.
/// - `GroqDirectConnectionPool` keeps the direct TLS connection open and
///   reusable, and can open it while the user is still speaking.
enum GroqDirectTransport {
    struct NetworkBlocked: LocalizedError {
        var errorDescription: String? {
            "Groq blocked this network connection. The direct connection also failed. Check your network or VPN settings and try again."
        }
    }

    static let blockedMessage = "Access denied. Please check your network settings."

    static let pool = GroqDirectConnectionPool(
        host: "api.groq.com",
        port: 443,
        usesTLS: true,
        bindsToPhysicalInterface: true
    )

    /// Only plain HTTPS requests to api.groq.com on the default port qualify.
    static func isEligible(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.groq.com",
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil,
              request.httpBodyStream == nil else { return false }
        return true
    }

    static func isNetworkBlock(_ result: (Data, URLResponse), request: URLRequest) -> Bool {
        guard isEligible(request),
              (result.1 as? HTTPURLResponse)?.statusCode == 403,
              let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return false }
        return error["message"] as? String == blockedMessage
    }

    static func send(_ request: URLRequest, body: Data?) async throws -> (Data, URLResponse) {
        try await send(request, body: body, pool: pool)
    }

    static func send(
        _ request: URLRequest,
        body: Data?,
        pool: GroqDirectConnectionPool
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        guard isEligible(request), let url = request.url else { throw NetworkBlocked() }
        let response = try await pool.send(request, body: body)
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        ) else { throw NetworkBlocked() }
        return (response.body, httpResponse)
    }

    /// Opens the direct connection ahead of time when Groq is known to block
    /// the current network path.
    @discardableResult
    static func prewarmIfBlocked(_ request: URLRequest, memory: GroqRouteMemory = .shared) -> Bool {
        guard memory.isBlocked, isEligible(request) else { return false }
        pool.prewarm()
        return true
    }
}

/// Remembers, for the life of the app, that Groq rejected the default network
/// path. Not persisted: the first request after launch probes again.
final class GroqRouteMemory: @unchecked Sendable {
    static let shared = GroqRouteMemory()

    private let lock = NSLock()
    private var blocked = false

    var isBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return blocked
    }

    func markBlocked() {
        lock.lock()
        blocked = true
        lock.unlock()
    }

    func clear() {
        lock.lock()
        blocked = false
        lock.unlock()
    }
}

/// Keep-alive HTTP/1.1 connections to a single host, optionally pinned to the
/// physical interface so VPN tunnels are bypassed. All mutable state is
/// confined to `queue`.
final class GroqDirectConnectionPool: @unchecked Sendable {
    private struct IdleConnection {
        let connection: NWConnection
        let openedAt: Date
    }

    let host: NWEndpoint.Host
    let port: NWEndpoint.Port
    private let usesTLS: Bool
    private let bindsToPhysicalInterface: Bool
    private let idleLifetime: TimeInterval
    private let maximumIdleConnections = 2
    private let queue = DispatchQueue(label: "FreeFlow.GroqDirectConnectionPool")

    private var idle: [IdleConnection] = []
    private var prewarming = 0
    private var monitor: NWPathMonitor?
    private var physicalInterface: NWInterface?

    /// Connections opened, for tests and diagnostics. Read on `queue`.
    private var openedConnections = 0

    init(
        host: String,
        port: UInt16,
        usesTLS: Bool,
        bindsToPhysicalInterface: Bool,
        idleLifetime: TimeInterval = 120
    ) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port) ?? .https
        self.usesTLS = usesTLS
        self.bindsToPhysicalInterface = bindsToPhysicalInterface
        self.idleLifetime = idleLifetime
        if bindsToPhysicalInterface {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                self?.updatePhysicalInterface(from: path)
            }
            monitor.start(queue: queue)
            self.monitor = monitor
        }
    }

    deinit {
        monitor?.cancel()
    }

    var connectionsOpened: Int {
        queue.sync { openedConnections }
    }

    private func updatePhysicalInterface(from path: NWPath) {
        let next = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }
        guard next?.name != physicalInterface?.name else { return }
        physicalInterface = next
        // Connections pinned to an interface that changed are no longer useful.
        dropIdleConnections()
    }

    private func dropIdleConnections() {
        let connections = idle.map(\.connection)
        idle.removeAll()
        for connection in connections {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
    }

    fileprivate func makeConnection() -> NWConnection {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        let parameters: NWParameters
        if usesTLS {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_add_tls_application_protocol(tls.securityProtocolOptions, "http/1.1")
            parameters = NWParameters(tls: tls, tcp: tcp)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcp)
        }
        parameters.preferNoProxies = true
        if bindsToPhysicalInterface {
            // Tunnels report the "other" type; keep them and loopback out.
            parameters.prohibitedInterfaceTypes = [.other, .loopback]
            if let physicalInterface { parameters.requiredInterface = physicalInterface }
        }
        openedConnections += 1
        return NWConnection(host: host, port: port, using: parameters)
    }

    fileprivate func takeIdleConnection() -> (connection: NWConnection, openedAt: Date)? {
        let now = Date()
        while let candidate = idle.popLast() {
            if now.timeIntervalSince(candidate.openedAt) < idleLifetime,
               case .ready = candidate.connection.state {
                return (candidate.connection, candidate.openedAt)
            }
            candidate.connection.stateUpdateHandler = nil
            candidate.connection.cancel()
        }
        return nil
    }

    fileprivate func storeIdleConnection(_ connection: NWConnection, openedAt: Date) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .failed, .cancelled, .waiting:
                guard let self, let connection else { return }
                self.idle.removeAll { $0.connection === connection }
                connection.cancel()
            default:
                break
            }
        }
        idle.append(IdleConnection(connection: connection, openedAt: openedAt))
        while idle.count > maximumIdleConnections {
            let oldest = idle.removeFirst()
            oldest.connection.stateUpdateHandler = nil
            oldest.connection.cancel()
        }
    }

    private final class Warmup: @unchecked Sendable {
        let connection: NWConnection
        let openedAt = Date()
        var settled = false
        init(connection: NWConnection) { self.connection = connection }
    }

    private func settle(_ warmup: Warmup, ready: Bool) {
        guard !warmup.settled else { return }
        warmup.settled = true
        prewarming -= 1
        if ready {
            storeIdleConnection(warmup.connection, openedAt: warmup.openedAt)
        } else {
            warmup.connection.stateUpdateHandler = nil
            warmup.connection.cancel()
        }
    }

    /// Opens one connection in the background if none is ready to reuse.
    func prewarm() {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            let hasFresh = self.idle.contains {
                now.timeIntervalSince($0.openedAt) < self.idleLifetime / 2
            }
            guard !hasFresh, self.prewarming == 0 else { return }
            self.prewarming += 1
            let warmup = Warmup(connection: self.makeConnection())
            warmup.connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.settle(warmup, ready: true)
                case .failed, .waiting, .cancelled: self?.settle(warmup, ready: false)
                default: break
                }
            }
            warmup.connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.settle(warmup, ready: false)
            }
        }
    }

    func send(_ request: URLRequest, body: Data?) async throws -> HTTP1Codec.Response {
        let bytes: Data
        do {
            bytes = try HTTP1Codec.requestData(for: request, body: body)
        } catch {
            throw URLError(.badURL)
        }
        let timeout = request.timeoutInterval.isFinite && request.timeoutInterval > 0 ? request.timeoutInterval : 60
        let exchange = Exchange(
            pool: self,
            requestBytes: bytes,
            method: request.httpMethod ?? "GET",
            deadline: .now() + timeout
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exchange.begin(continuation)
            }
        } onCancel: {
            exchange.cancel()
        }
    }

    /// One request/response on the pool's queue, with at most one retry on a
    /// fresh connection when a reused one turns out to be already closed.
    private final class Exchange: @unchecked Sendable {
        private let pool: GroqDirectConnectionPool
        private let requestBytes: Data
        private let method: String
        private let deadline: DispatchTime
        private var continuation: CheckedContinuation<HTTP1Codec.Response, Error>?
        private var connection: NWConnection?
        private var connectionOpenedAt = Date()
        private var reader: HTTP1Codec.ResponseReader
        private var reused = false
        private var sent = false
        private var retriedFresh = false
        private var finished = false
        private var cancelled = false

        init(pool: GroqDirectConnectionPool, requestBytes: Data, method: String, deadline: DispatchTime) {
            self.pool = pool
            self.requestBytes = requestBytes
            self.method = method
            self.deadline = deadline
            reader = HTTP1Codec.ResponseReader(method: method)
        }

        private var queue: DispatchQueue { pool.queue }

        func begin(_ continuation: CheckedContinuation<HTTP1Codec.Response, Error>) {
            queue.async {
                self.continuation = continuation
                guard !self.cancelled else {
                    self.fail(CancellationError())
                    return
                }
                // Strong capture keeps the exchange alive until its deadline at most.
                self.queue.asyncAfter(deadline: self.deadline) {
                    self.fail(URLError(.timedOut))
                }
                if let idle = self.pool.takeIdleConnection() {
                    self.attach(idle.connection, reused: true, openedAt: idle.openedAt)
                } else {
                    self.attach(self.pool.makeConnection(), reused: false, openedAt: Date())
                }
            }
        }

        func cancel() {
            queue.async {
                self.cancelled = true
                if self.continuation != nil { self.fail(CancellationError()) }
            }
        }

        private func attach(_ connection: NWConnection, reused: Bool, openedAt: Date) {
            self.connection = connection
            self.reused = reused
            connectionOpenedAt = openedAt
            sent = false
            reader = HTTP1Codec.ResponseReader(method: method)
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, connection === self.connection else { return }
                switch state {
                case .ready:
                    self.sendRequest(on: connection)
                case .failed(let error), .waiting(let error):
                    self.connectionFailed(connection, error: error)
                case .cancelled:
                    self.connectionFailed(connection, error: nil)
                default:
                    break
                }
            }
            if reused {
                sendRequest(on: connection)
            } else {
                connection.start(queue: queue)
            }
        }

        private func sendRequest(on connection: NWConnection) {
            guard !finished, !sent else { return }
            sent = true
            connection.send(content: requestBytes, completion: .contentProcessed { [weak self] error in
                guard let self, connection === self.connection else { return }
                if let error {
                    self.connectionFailed(connection, error: error)
                } else {
                    self.receive(on: connection)
                }
            })
        }

        private func receive(on connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self, !self.finished, connection === self.connection else { return }
                do {
                    if let data, !data.isEmpty { try self.reader.consume(data) }
                    if let response = self.reader.response {
                        self.succeed(response, connection: connection, peerClosed: isComplete)
                        return
                    }
                    // A close before any byte is a dead connection, not a bad response.
                    if isComplete, self.reader.receivedAnyBytes {
                        try self.reader.finish()
                        if let response = self.reader.response {
                            self.succeed(response, connection: connection, peerClosed: true)
                            return
                        }
                    }
                } catch {
                    self.fail(URLError(.badServerResponse))
                    return
                }
                if isComplete || error != nil {
                    self.connectionFailed(connection, error: error)
                } else {
                    self.receive(on: connection)
                }
            }
        }

        private func connectionFailed(_ connection: NWConnection, error: NWError?) {
            guard !finished else { return }
            connection.stateUpdateHandler = nil
            connection.cancel()
            if reused, !reader.receivedAnyBytes, !retriedFresh, !cancelled {
                // The server had already closed the idle connection.
                retriedFresh = true
                attach(pool.makeConnection(), reused: false, openedAt: Date())
                return
            }
            if case .posix(let code)? = error, code == .ETIMEDOUT {
                fail(URLError(.timedOut))
            } else {
                fail(URLError(.networkConnectionLost))
            }
        }

        private func succeed(_ response: HTTP1Codec.Response, connection: NWConnection, peerClosed: Bool) {
            guard !finished else { return }
            finished = true
            if response.reusable, !peerClosed {
                pool.storeIdleConnection(connection, openedAt: connectionOpenedAt)
            } else {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
            self.connection = nil
            continuation?.resume(returning: response)
            continuation = nil
        }

        private func fail(_ error: Error) {
            guard !finished else { return }
            finished = true
            if let connection {
                connection.stateUpdateHandler = nil
                connection.cancel()
                self.connection = nil
            }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
