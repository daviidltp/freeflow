import Foundation

enum LLMAPITransport {
    typealias DirectTransport = (URLRequest, Data?) async throws -> (Data, URLResponse)

    /// One provider operation: the default session first and, only for Groq's
    /// exact VPN block, the direct physical-interface route. Shares a single
    /// timeout budget across both routes and the temperature retry.
    private final class Route {
        private let deadline: Date
        private let direct: DirectTransport
        private let memory: GroqRouteMemory
        private var directUsed = false
        private var rememberedRouteFailed = false

        init(request: URLRequest, direct: @escaping DirectTransport, memory: GroqRouteMemory) {
            deadline = Date().addingTimeInterval(LLMAPITransport.timeout(for: request))
            self.direct = direct
            self.memory = memory
        }

        private func remainingBudget() throws -> TimeInterval {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw URLError(.timedOut) }
            return remaining
        }

        func send(_ request: URLRequest, body: Data? = nil, session: URLSession) async throws -> (Data, URLResponse) {
            try Task.checkCancellation()
            var outgoing = request
            outgoing.timeoutInterval = try remainingBudget()
            if directUsed { return try await sendDirect(outgoing, body: body) }

            if !rememberedRouteFailed, memory.isBlocked, GroqDirectTransport.isEligible(outgoing) {
                // Groq already rejected the default path: skip the doomed attempt.
                let remembered: (Data, URLResponse)?
                do {
                    remembered = try await direct(outgoing, body)
                } catch {
                    try Task.checkCancellation()
                    if (error as? URLError)?.code == .timedOut { throw error }
                    remembered = nil
                }
                try Task.checkCancellation()
                if let remembered, !GroqDirectTransport.isNetworkBlock(remembered, request: outgoing) {
                    directUsed = true
                    return remembered
                }
                // The direct path failed or is blocked too; forget and probe the default path.
                memory.clear()
                rememberedRouteFailed = true
                outgoing.timeoutInterval = try remainingBudget()
            }

            let result: (Data, URLResponse)
            if let body { result = try await session.upload(for: outgoing, from: body) }
            else { result = try await session.data(for: outgoing) }
            guard GroqDirectTransport.isNetworkBlock(result, request: outgoing) else { return result }
            memory.markBlocked()
            directUsed = true
            outgoing.timeoutInterval = try remainingBudget()
            return try await sendDirect(outgoing, body: body)
        }

        private func sendDirect(_ request: URLRequest, body: Data?) async throws -> (Data, URLResponse) {
            let result: (Data, URLResponse)
            do {
                result = try await direct(request, body)
            } catch {
                try Task.checkCancellation()
                if let error = error as? URLError, error.code == .timedOut { throw error }
                throw GroqDirectTransport.NetworkBlocked()
            }
            try Task.checkCancellation()
            if GroqDirectTransport.isNetworkBlock(result, request: request) {
                memory.clear()
                throw GroqDirectTransport.NetworkBlocked()
            }
            return result
        }
    }

    /// Sesión compartida entre dictados: reutiliza la conexión TLS/HTTP con el
    /// proveedor en vez de abrir una nueva por petición. Cada petición sigue
    /// llevando su propio timeout en el URLRequest, y quien llama ya corta por
    /// tiempo total con su propia carrera de timeout.
    private static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 300
        return URLSession(configuration: configuration)
    }()

    private static func makeEphemeralSession(timeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }

    private static func timeout(for request: URLRequest) -> TimeInterval {
        let requestTimeout = request.timeoutInterval
        guard requestTimeout.isFinite, requestTimeout > 0 else {
            return 60
        }
        return requestTimeout
    }

    /// Una conexión reutilizada que el servidor ya cerró falla con
    /// `networkConnectionLost`. En ese caso se repite una vez con una sesión
    /// nueva, que es lo que se hacía siempre antes.
    static func isStaleConnectionError(_ error: Error) -> Bool {
        (error as? URLError)?.code == .networkConnectionLost
    }

    /// The retry gets only what is left of the request's timeout, so one
    /// operation never takes longer than its configured budget.
    private static func withFreshSessionOnStaleConnection<T>(
        request: URLRequest,
        _ operation: (URLSession, URLRequest) async throws -> T
    ) async throws -> T {
        let budget = timeout(for: request)
        let startedAt = Date()
        do {
            return try await operation(sharedSession, request)
        } catch where isStaleConnectionError(error) {
            let remaining = budget - Date().timeIntervalSince(startedAt)
            guard remaining > 0 else { throw URLError(.timedOut) }
            var retry = request
            retry.timeoutInterval = remaining
            let session = makeEphemeralSession(timeout: remaining)
            defer { session.finishTasksAndInvalidate() }
            return try await operation(session, retry)
        }
    }

    /// Abre la conexión con el proveedor mientras el usuario habla, para que la
    /// subida del audio no pague DNS + TCP + TLS al soltar la tecla. Es un HEAD
    /// sin credenciales: no consume cuota del proveedor.
    static func prewarm(baseURL: String) {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        // With a VPN that Groq blocks, warm the direct route the request will use.
        if GroqDirectTransport.prewarmIfBlocked(request) { return }
        sharedSession.dataTask(with: request).resume()
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await withFreshSessionOnStaleConnection(request: request) { session, request in
            try await data(for: request, using: session)
        }
    }

    static func data(
        for request: URLRequest,
        cache: TemperatureCapabilityCache
    ) async throws -> (Data, URLResponse) {
        try await withFreshSessionOnStaleConnection(request: request) { session, request in
            try await data(for: request, using: session, cache: cache)
        }
    }

    static func data(
        for request: URLRequest,
        using session: URLSession
    ) async throws -> (Data, URLResponse) {
        try await data(for: request, using: session, cache: TemperatureCapabilityCache.shared)
    }

    static func data(
        for request: URLRequest,
        using session: URLSession,
        cache: TemperatureCapabilityCache,
        direct: @escaping DirectTransport = GroqDirectTransport.send,
        memory: GroqRouteMemory = .shared
    ) async throws -> (Data, URLResponse) {
        let route = Route(request: request, direct: direct, memory: memory)
        let observation = cache.beginObservation(for: request)
        let capability = observation.capability
        let outgoing = capability == .unsupported ? requestWithoutTemperature(request) ?? request : request
        let result = try await route.send(outgoing, session: session)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 200,
           isValidCompletionResponse(result.0), payloadHasTemperature(outgoing) {
            cache.record(.supported, for: outgoing, observation: observation)
        }
        guard capability != .unsupported,
              let response = result.1 as? HTTPURLResponse,
              response.statusCode == 400,
              let retry = requestWithoutUnsupportedTemperature(outgoing, errorData: result.0) else {
            return result
        }
        cache.record(.unsupported, for: outgoing, observation: observation)
        let retried = try await route.send(retry, session: session)
        return retried
    }

    private static func payloadHasTemperature(_ request: URLRequest) -> Bool {
        guard let body = request.httpBody,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
        return payload["temperature"] != nil
    }

    private static func isValidCompletionResponse(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]], !choices.isEmpty,
              let message = choices[0]["message"] as? [String: Any] else { return false }
        return message["content"] != nil || message["reasoning"] != nil
    }

    private static func requestWithoutTemperature(_ request: URLRequest) -> URLRequest? {
        guard let body = request.httpBody,
              var payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              payload.removeValue(forKey: "temperature") != nil,
              let retryBody = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var retry = request
        retry.httpBody = retryBody
        return retry
    }

    private static func requestWithoutUnsupportedTemperature(
        _ request: URLRequest,
        errorData: Data
    ) -> URLRequest? {
        guard request.httpBody != nil,
              let error = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
              let details = error["error"] as? [String: Any] else {
            return nil
        }
        let code = (details["code"] as? String ?? "").lowercased()
        let param = (details["param"] as? String ?? "").lowercased()
        let message = (details["message"] as? String ?? "").lowercased()
        let unsupportedCode = code == "unsupported_parameter" || code == "unsupported_value"
        let unsupportedMessage = message.contains("unsupported") ||
            message.contains("not supported") || message.contains("does not support")
        guard unsupportedCode && param == "temperature" && unsupportedMessage else {
            return nil
        }
        return requestWithoutTemperature(request)
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data
    ) async throws -> (Data, URLResponse) {
        try await withFreshSessionOnStaleConnection(request: request) { session, request in
            try await upload(for: request, from: bodyData, using: session)
        }
    }

    static func upload(
        for request: URLRequest,
        from bodyData: Data,
        using session: URLSession,
        direct: @escaping DirectTransport = GroqDirectTransport.send,
        memory: GroqRouteMemory = .shared
    ) async throws -> (Data, URLResponse) {
        try await Route(request: request, direct: direct, memory: memory)
            .send(request, body: bodyData, session: session)
    }
}
