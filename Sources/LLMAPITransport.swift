import Foundation

enum LLMAPITransport {
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

    private static func withFreshSessionOnStaleConnection<T>(
        timeout: TimeInterval,
        _ operation: (URLSession) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(sharedSession)
        } catch where isStaleConnectionError(error) {
            let session = makeEphemeralSession(timeout: timeout)
            defer { session.finishTasksAndInvalidate() }
            return try await operation(session)
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
        sharedSession.dataTask(with: request).resume()
    }

    static func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await withFreshSessionOnStaleConnection(timeout: timeout(for: request)) { session in
            try await data(for: request, using: session)
        }
    }

    static func data(
        for request: URLRequest,
        cache: TemperatureCapabilityCache
    ) async throws -> (Data, URLResponse) {
        try await withFreshSessionOnStaleConnection(timeout: timeout(for: request)) { session in
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
        cache: TemperatureCapabilityCache
    ) async throws -> (Data, URLResponse) {
        let observation = cache.beginObservation(for: request)
        let capability = observation.capability
        let outgoing = capability == .unsupported ? requestWithoutTemperature(request) ?? request : request
        let result = try await session.data(for: outgoing)
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
        let retried = try await session.data(for: retry)
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
        try await withFreshSessionOnStaleConnection(timeout: timeout(for: request)) { session in
            try await session.upload(for: request, from: bodyData)
        }
    }
}
