import Foundation

private final class StubLLMURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { fatalError("Missing test handler") }
        Self.requests.append(request)
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func bodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: 4096)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data
}

enum LLMAPITransportTests {
    static func run() async {
        await networkFallbackTests()
        await rememberedBlockTests()
        func perform(_ replies: [(Int, String)], body payload: [String: Any] = ["model": "fixture", "temperature": 0, "top_p": 0.7, "max_completion_tokens": 128, "messages": []], endpoint: String = UUID().uuidString, cache: TemperatureCapabilityCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-\(UUID().uuidString)")!)) async throws -> [URLRequest] {
            StubLLMURLProtocol.requests = []
            var remaining = replies
            StubLLMURLProtocol.handler = { _ in
                let next = remaining.removeFirst()
                return (next.0, Data(next.1.utf8))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [StubLLMURLProtocol.self]
            let session = URLSession(configuration: configuration)
            let body = try JSONSerialization.data(withJSONObject: payload)
            var request = URLRequest(url: URL(string: "https://provider.invalid/\(endpoint)/chat")!)
            request.httpMethod = "POST"
            request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            let (_, response) = try await LLMAPITransport.data(for: request, using: session, cache: cache)
            session.invalidateAndCancel()
            _ = response
            return StubLLMURLProtocol.requests
        }

        let rejected = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":\"temperature\",\"message\":\"temperature is unsupported\"}}"
        let accepted = "{\"choices\":[]}"
        let retry = try! await perform([(400, rejected), (200, accepted)])
        TestSupport.expect(retry.count == 2, "Unsupported temperature should retry once")
        let original = try! JSONSerialization.jsonObject(with: bodyData(retry[0])!) as! [String: Any]
        let retried = try! JSONSerialization.jsonObject(with: bodyData(retry[1])!) as! [String: Any]
        TestSupport.expect(original["temperature"] != nil, "Initial body retains temperature")
        TestSupport.expect(retried["temperature"] == nil && retried["model"] as? String == "fixture" && retried["messages"] != nil && retried["top_p"] as? Double == 0.7 && retried["max_completion_tokens"] as? Int == 128, "Retry removes only temperature")
        TestSupport.expect(retry.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-token" && $0.value(forHTTPHeaderField: "Content-Type") == "application/json" }, "Retry preserves authorization and content type")

        let openAIStyle = "{\"error\":{\"code\":\"unsupported_value\",\"param\":\"temperature\",\"message\":\"Unsupported value: 'temperature' does not support 0 with this model. Only the default (1) value is supported.\"}}"
        let openAIRetry = try! await perform([(400, openAIStyle), (200, accepted)])
        TestSupport.expect(openAIRetry.count == 2, "OpenAI unsupported_value response retries once")

        let otherParameter = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":\"max_tokens\",\"message\":\"Unsupported parameter\"}}"
        let wrongParam = try! await perform([(400, otherParameter)])
        TestSupport.expect(wrongParam.count == 1, "Unsupported parameter other than temperature does not retry")

        let nullParam = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":null,\"message\":\"temperature is not supported with this model\"}}"
        let nullParamResult = try! await perform([(400, nullParam)])
        TestSupport.expect(nullParamResult.count == 1, "Missing temperature parameter identity does not retry")

        let mixedParameter = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":null,\"message\":\"temperature is supported; top_p is unsupported\"}}"
        let mixedParameterResult = try! await perform([(400, mixedParameter)])
        TestSupport.expect(mixedParameterResult.count == 1, "Mixed-parameter rejection does not remove temperature")

        let unrelatedMessage = "{\"error\":{\"code\":\"unsupported_parameter\",\"param\":\"temperature\",\"message\":\"value must be between 0 and 2\"}}"
        let unrelatedMessageResult = try! await perform([(400, unrelatedMessage)])
        TestSupport.expect(unrelatedMessageResult.count == 1, "Temperature validation errors do not imply unsupported capability")

        let success = try! await perform([(200, accepted)])
        TestSupport.expect(success.count == 1, "Successful call does not retry")
        let retained = try! JSONSerialization.jsonObject(with: bodyData(success[0])!) as! [String: Any]
        TestSupport.expect(retained["temperature"] != nil, "Compatible call retains temperature")

        let unrelated = try! await perform([(400, "{\"error\":{\"code\":\"invalid_api_key\",\"message\":\"bad key\"}}")])
        TestSupport.expect(unrelated.count == 1, "Unrelated 400 does not retry")
        let noTemperature = try! await perform([(400, rejected)], body: ["model": "fixture", "messages": []])
        TestSupport.expect(noTemperature.count == 1, "Request without temperature does not retry")

        let rejectedAgain = try! await perform([(400, rejected), (400, rejected)])
        TestSupport.expect(rejectedAgain.count == 2, "Second rejection stops after one retry")

        let persistentCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-persistent-\(UUID().uuidString)")!)
        let endpoint = UUID().uuidString
        let first = try! await perform([(400, rejected), (200, accepted)], endpoint: endpoint, cache: persistentCache)
        let subsequent = try! await perform([(200, accepted)], endpoint: endpoint, cache: persistentCache)
        let omittedBody = try! JSONSerialization.jsonObject(with: bodyData(subsequent[0])!) as! [String: Any]
        TestSupport.expect(first.count == 2 && subsequent.count == 1 && omittedBody["temperature"] == nil, "Runtime rejection is cached and subsequent call omits temperature")

        let staleSuite = "transport-stale-\(UUID().uuidString)"
        let staleDefaults = UserDefaults(suiteName: staleSuite)!
        defer { staleDefaults.removePersistentDomain(forName: staleSuite) }
        let staleCache = TemperatureCapabilityCache(defaults: staleDefaults)
        let sharedEndpoint = UUID().uuidString
        var sharedRequest = URLRequest(url: URL(string: "https://provider.invalid/\(sharedEndpoint)/chat")!)
        sharedRequest.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
        sharedRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sharedRequest.httpBody = try! JSONSerialization.data(withJSONObject: ["model": "fixture", "temperature": 0, "top_p": 0.7, "max_completion_tokens": 128, "messages": []])
        let staleObservation = staleCache.beginObservation(for: sharedRequest)
        _ = try! await perform([(400, rejected), (200, accepted)], endpoint: sharedEndpoint, cache: staleCache)
        staleCache.record(.supported, for: sharedRequest, observation: staleObservation)
        TestSupport.expect(staleCache.capability(for: sharedRequest) == .unsupported, "Cache ignores stale success after newer runtime rejection")

        let supportedCache = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-supported-\(UUID().uuidString)")!)
        let supportedEndpoint = UUID().uuidString
        let validCompletion = "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"OK\"}}]}"
        _ = try! await perform([(200, validCompletion)], endpoint: supportedEndpoint, cache: supportedCache)
        let supportedCall = try! await perform([(200, validCompletion)], endpoint: supportedEndpoint, cache: supportedCache)
        let supportedBody = try! JSONSerialization.jsonObject(with: bodyData(supportedCall[0])!) as! [String: Any]
        TestSupport.expect(supportedCall.count == 1 && supportedBody["temperature"] != nil, "Successful supported response preserves temperature on later calls")

        for (status, body, label) in [
            (401, "{\"error\":{\"code\":\"invalid_api_key\",\"message\":\"bad key\"}}", "auth"),
            (429, "{\"error\":{\"code\":\"rate_limit_exceeded\"}}", "rate limit"),
            (400, "{\"error\":{\"code\":\"invalid_request\",\"message\":\"bad request\"}}", "unrelated 400")
        ] {
            let isolated = TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "transport-\(label)-\(UUID().uuidString)")!)
            let isolatedEndpoint = UUID().uuidString
            _ = try! await perform([(status, body)], endpoint: isolatedEndpoint, cache: isolated)
            let next = try! await perform([(200, validCompletion)], endpoint: isolatedEndpoint, cache: isolated)
            let nextBody = try! JSONSerialization.jsonObject(with: bodyData(next[0])!) as! [String: Any]
            TestSupport.expect(next.count == 1 && nextBody["temperature"] != nil, "\(label) errors do not poison capability cache")
        }
    }
}

extension LLMAPITransportTests {
    private static let blocked = Data(#"{"error":{"message":"Access denied. Please check your network settings."}}"#.utf8)

    private static func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubLLMURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func groqRequest(timeout: TimeInterval = 12) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"model":"fixture","temperature":0,"messages":[]}"#.utf8)
        request.setValue("Bearer synthetic-token", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func response(_ request: URLRequest, _ status: Int, _ body: Data) -> (Data, URLResponse) {
        (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private static func freshCache() -> TemperatureCapabilityCache {
        TemperatureCapabilityCache(defaults: UserDefaults(suiteName: "vpn-tests-\(UUID().uuidString)")!)
    }

    static func networkFallbackTests() async {
        let session = stubSession()
        defer { session.invalidateAndCancel() }
        let cache = freshCache()
        let request = groqRequest()
        StubLLMURLProtocol.handler = { _ in (403, blocked) }
        var directRequests: [URLRequest] = []
        let direct: LLMAPITransport.DirectTransport = { outgoing, body in
            TestSupport.expect(body == nil, "Data fallback uses original request body")
            directRequests.append(outgoing)
            return response(outgoing, 401, Data())
        }
        let memory = GroqRouteMemory()
        let result = try! await LLMAPITransport.data(for: request, using: session, cache: cache, direct: direct, memory: memory)
        TestSupport.expect((result.1 as? HTTPURLResponse)?.statusCode == 401 && directRequests.count == 1, "Groq network block reaches direct route once")
        TestSupport.expect(memory.isBlocked, "Observed Groq network block is remembered")
        TestSupport.expect(directRequests[0].httpBody == request.httpBody && directRequests[0].allHTTPHeaderFields == request.allHTTPHeaderFields && directRequests[0].httpMethod == "POST", "Fallback preserves body, method and headers")
        TestSupport.expect(directRequests[0].timeoutInterval > 0 && directRequests[0].timeoutInterval <= 12, "Fallback shares original timeout budget")
        for url in ["http://api.groq.com/test", "https://other.invalid/test", "https://api.groq.com.evil.invalid/test", "https://api.groq.com:444/test"] {
            var other = request
            other.url = URL(string: url)!
            let otherMemory = GroqRouteMemory()
            let original = try! await LLMAPITransport.data(for: other, using: session, cache: cache, direct: { _, _ in fatalError("Unsafe fallback") }, memory: otherMemory)
            TestSupport.expect((original.1 as? HTTPURLResponse)?.statusCode == 403 && !otherMemory.isBlocked, "Other provider/scheme/port preserves original error")
        }
        for (status, body) in [(403, Data(#"{"error":{"message":"Key lacks permission"}}"#.utf8)), (401, blocked), (429, blocked), (403, Data("Access denied. Please check your network settings.".utf8))] {
            StubLLMURLProtocol.handler = { _ in (status, body) }
            let unrelatedMemory = GroqRouteMemory()
            _ = try! await LLMAPITransport.data(for: request, using: session, cache: cache, direct: { _, _ in fatalError("Unrelated error bypassed VPN") }, memory: unrelatedMemory)
            TestSupport.expect(!unrelatedMemory.isBlocked, "Unrelated errors are not remembered as a network block")
        }
        StubLLMURLProtocol.handler = { _ in (403, blocked) }
        var attempts = 0
        let repeatedMemory = GroqRouteMemory()
        do {
            _ = try await LLMAPITransport.data(for: request, using: session, cache: cache, direct: { outgoing, _ in
                attempts += 1
                return response(outgoing, 403, blocked)
            }, memory: repeatedMemory)
            fatalError("Repeated block must report network failure")
        } catch {
            TestSupport.expect(error is GroqDirectTransport.NetworkBlocked && attempts == 1, "Repeated block stops once with network-specific error")
            TestSupport.expect(!error.localizedDescription.contains("key"), "Network block must not blame key permissions")
            TestSupport.expect(!repeatedMemory.isBlocked, "A block on the direct route too is not remembered")
        }
        let audio = Data([0, 1, 255, 13, 10])
        let upload = try! await LLMAPITransport.upload(for: request, from: audio, using: session, direct: { outgoing, body in
            TestSupport.expect(body == audio && outgoing.allHTTPHeaderFields == request.allHTTPHeaderFields, "Upload fallback preserves binary multipart payload and headers")
            return response(outgoing, 200, Data("synthetic transcript".utf8))
        }, memory: GroqRouteMemory())
        TestSupport.expect((upload.1 as? HTTPURLResponse)?.statusCode == 200, "Upload uses fallback")
        attempts = 0
        let rejected = Data(#"{"error":{"code":"unsupported_parameter","param":"temperature","message":"temperature is unsupported"}}"#.utf8)
        let success = Data(#"{"choices":[{"message":{"content":"OK"}}]}"#.utf8)
        StubLLMURLProtocol.requests = []
        _ = try! await LLMAPITransport.data(for: request, using: session, cache: cache, direct: { outgoing, _ in
            attempts += 1
            let json = try! JSONSerialization.jsonObject(with: outgoing.httpBody!) as! [String: Any]
            TestSupport.expect((json["temperature"] != nil) == (attempts == 1), "Temperature retry works after switching route")
            return response(outgoing, attempts == 1 ? 400 : 200, attempts == 1 ? rejected : success)
        }, memory: GroqRouteMemory())
        TestSupport.expect(attempts == 2 && StubLLMURLProtocol.requests.count == 1 && cache.capability(for: request) == .unsupported, "Temperature cache survives direct route retry without a second VPN attempt")
        do {
            _ = try await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: { _, _ in throw URLError(.timedOut) }, memory: GroqRouteMemory())
            fatalError("Timeout must propagate")
        } catch {
            TestSupport.expect((error as? URLError)?.code == .timedOut, "Direct timeout remains timeout")
        }
        var entered: AsyncStream<Void>.Continuation!
        let started = AsyncStream<Void> { entered = $0 }
        let cancelled = Task {
            _ = try await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: { _, _ in
                entered.yield(())
                try await Task.sleep(nanoseconds: 30_000_000_000)
                fatalError("Cancelled fallback continued")
            }, memory: GroqRouteMemory())
        }
        for await _ in started { break }
        cancelled.cancel()
        entered.finish()
        do { try await cancelled.value; fatalError("Cancellation lost") }
        catch { TestSupport.expect(error is CancellationError || (error as? URLError)?.code == .cancelled, "Cancellation propagates") }
        var foreign = request
        foreign.url = URL(string: "https://other.invalid")!
        do { _ = try await GroqDirectTransport.send(foreign, body: nil); fatalError("Foreign host reached direct route") }
        catch { TestSupport.expect(error is GroqDirectTransport.NetworkBlocked, "Direct adapter enforces host independently") }
    }

    /// Once Groq blocked the default path, later operations must not pay for a
    /// doomed upload through the VPN before going direct.
    static func rememberedBlockTests() async {
        let session = stubSession()
        defer { session.invalidateAndCancel() }
        let request = groqRequest()
        let memory = GroqRouteMemory()
        StubLLMURLProtocol.handler = { _ in (403, blocked) }
        StubLLMURLProtocol.requests = []
        var directCalls = 0
        let direct: LLMAPITransport.DirectTransport = { outgoing, _ in
            directCalls += 1
            return response(outgoing, 200, Data("ok".utf8))
        }
        _ = try! await LLMAPITransport.upload(for: request, from: Data([1, 2, 3]), using: session, direct: direct, memory: memory)
        TestSupport.expect(StubLLMURLProtocol.requests.count == 1 && directCalls == 1 && memory.isBlocked, "First operation probes default route, then goes direct and remembers")
        _ = try! await LLMAPITransport.upload(for: request, from: Data([4, 5, 6]), using: session, direct: direct, memory: memory)
        _ = try! await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: direct, memory: memory)
        TestSupport.expect(StubLLMURLProtocol.requests.count == 1 && directCalls == 3, "Later uploads and completions skip the blocked default route")

        // Direct route stops working (network changed, VPN gone): forget and use default route.
        StubLLMURLProtocol.handler = { _ in (200, Data("default".utf8)) }
        StubLLMURLProtocol.requests = []
        let recovered = try! await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: { _, _ in
            throw URLError(.networkConnectionLost)
        }, memory: memory)
        TestSupport.expect(String(data: recovered.0, encoding: .utf8) == "default" && StubLLMURLProtocol.requests.count == 1 && !memory.isBlocked, "Failing remembered route falls back to default route and is forgotten")

        // Remembered route answers with the block itself: forget it and probe again.
        memory.markBlocked()
        StubLLMURLProtocol.requests = []
        var blockedDirectCalls = 0
        let probed = try! await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: { outgoing, _ in
            blockedDirectCalls += 1
            return response(outgoing, 403, blocked)
        }, memory: memory)
        TestSupport.expect((probed.1 as? HTTPURLResponse)?.statusCode == 200 && blockedDirectCalls == 1 && StubLLMURLProtocol.requests.count == 1 && !memory.isBlocked, "Blocked remembered route is forgotten and default route used")

        // A timeout on the remembered route spends the budget: no second attempt.
        memory.markBlocked()
        StubLLMURLProtocol.requests = []
        do {
            _ = try await LLMAPITransport.data(for: request, using: session, cache: freshCache(), direct: { _, _ in throw URLError(.timedOut) }, memory: memory)
            fatalError("Remembered timeout must propagate")
        } catch {
            TestSupport.expect((error as? URLError)?.code == .timedOut && StubLLMURLProtocol.requests.isEmpty, "Remembered route timeout propagates without default retry")
        }

        // Other providers never use the memory.
        var other = request
        other.url = URL(string: "https://provider.invalid/v1/chat/completions")!
        StubLLMURLProtocol.requests = []
        _ = try! await LLMAPITransport.data(for: other, using: session, cache: freshCache(), direct: { _, _ in fatalError("Other provider went direct") }, memory: memory)
        TestSupport.expect(StubLLMURLProtocol.requests.count == 1, "Other providers ignore remembered Groq block")
    }
}
