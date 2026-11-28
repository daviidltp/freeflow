import Foundation

enum TranscriptTextCoreTests {
    static func run() {
        testJSONTranscriptParsing()
        testNonTranscriptJSONFallsBackToUTF8()
        testInvalidTranscriptResponses()
        testHighConfidenceHallucinationsAreSuppressed()
        testPossibleRealSpeechIsPreserved()
        testSkippedSpeechDetection()
        testPostProcessedTranscriptSanitization()
        testModeSpecificSanitization()
        testInstructionExecutionGuard()
    }


    private static func testJSONTranscriptParsing() {
        let data = jsonData(["text": "Synthetic transcript."])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(data),
            "Synthetic transcript."
        )

        let emptyData = jsonData(["text": ""])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(emptyData), "")
    }

    private static func testNonTranscriptJSONFallsBackToUTF8() {
        let data = Data("{\n  \"synthetic\": \"fallback\"\n}".utf8)
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(data),
            "{   \"synthetic\": \"fallback\" }"
        )
    }

    private static func testInvalidTranscriptResponses() {
        expectInvalidResponse(Data())
        expectInvalidResponse(Data(" \n\t ".utf8))
        expectInvalidResponse(Data("{malformed synthetic JSON".utf8))
        expectInvalidResponse(Data([0xFF, 0xFE]))
    }

    private static func testHighConfidenceHallucinationsAreSuppressed() {
        let atThreshold = jsonData([
            "text": "Thank you.",
            "segments": [["no_speech_prob": 0.1]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(atThreshold), "")

        let normalizedPhrase = jsonData([
            "text": "  THANK YOU FOR WATCHING!!!  ",
            "segments": [["no_speech_prob": 0.9]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(normalizedPhrase), "")
    }

    private static func testPossibleRealSpeechIsPreserved() {
        let lowProbability = jsonData([
            "text": "Thank you.",
            "segments": [["no_speech_prob": 0.099]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(lowProbability), "Thank you.")

        let missingMetadata = jsonData(["text": "Thank you."])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingMetadata), "Thank you.")

        let missingProbability = jsonData([
            "text": "Thank you.",
            "segments": [["synthetic": true]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingProbability), "Thank you.")

        let unrelatedSpeech = jsonData([
            "text": "Synthetic project update.",
            "segments": [["no_speech_prob": 0.95]]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(unrelatedSpeech),
            "Synthetic project update."
        )
    }

    private static func testPostProcessedTranscriptSanitization() {
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.postProcessedTranscript("  \"Synthetic output.\" \n"),
            "Synthetic output."
        )
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("EMPTY"), "")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("\"EMPTY\""), "")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("empty"), "empty")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("  \n "), "")
    }

    private static func testModeSpecificSanitization() {
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.verbatimTranslation("  \"EMPTY\"  "),
            "EMPTY"
        )
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.verbatimTranslation(" \"Literal synthetic text.\" "),
            "Literal synthetic text."
        )
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.commandModeTranscript("  \"Keep command quotes\" \n"),
            "\"Keep command quotes\""
        )
    }

    private static func testInstructionExecutionGuard() {
        TestSupport.expect(
            TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write an email asking Alex for the synthetic report.",
                cleanedTranscript: "Sure, here's a draft: Hello Alex, please send the report.",
                outputLanguage: ""
            ),
            "Assistant-style execution should be rejected"
        )
        TestSupport.expect(
            TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write a haiku about synthetic rain.",
                cleanedTranscript: "Soft drizzle taps windows.",
                outputLanguage: ""
            ),
            "Low-overlap instruction execution should be rejected"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write an email asking Alex for the synthetic report.",
                cleanedTranscript: "Write an email asking Alex for the synthetic report.",
                outputLanguage: ""
            ),
            "Faithful cleanup should preserve instruction wording"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "The synthetic launch is Friday.",
                cleanedTranscript: "Sure, the synthetic launch is Friday.",
                outputLanguage: ""
            ),
            "Ordinary speech without an instruction marker should not trigger the guard"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Translate the synthetic update.",
                cleanedTranscript: "Aggiornamento sintetico.",
                outputLanguage: "Italian"
            ),
            "Explicit translation output should bypass the instruction guard"
        )
    }

    private static func testSkippedSpeechDetection() {
        // Un tramo de 30 s resumido en 14 palabras: Whisper se saltó lo que se dijo.
        let skipped = jsonData([
            "text": "Primera parte dictada con normalidad. Una frase corta que resume medio minuto de voz sin parar.",
            "segments": [
                ["start": 0.0, "end": 12.0, "text": "Primera parte dictada con normalidad y bastantes palabras seguidas para llenar doce segundos de voz real aquí mismo ahora."],
                ["start": 28.1, "end": 58.1, "text": "Una frase corta que resume medio minuto de voz sin parar, de verdad."]
            ]
        ])
        TestSupport.expect(TranscriptionResponseParser.looksLikeSkippedSpeech(skipped), "long segment with few words is skipped speech")

        let normal = jsonData([
            "text": "Dictado normal.",
            "segments": [
                ["start": 0.0, "end": 13.0, "text": String(repeating: "palabra ", count: 19)],
                ["start": 13.0, "end": 15.0, "text": "y fin."]
            ]
        ])
        TestSupport.expect(!TranscriptionResponseParser.looksLikeSkippedSpeech(normal), "slow but complete dictation is not skipped speech")

        let shortPause = jsonData([
            "text": "Vale.",
            "segments": [["start": 0.0, "end": 6.0, "text": "Vale."]]
        ])
        TestSupport.expect(!TranscriptionResponseParser.looksLikeSkippedSpeech(shortPause), "short segments are never flagged")

        TestSupport.expect(!TranscriptionResponseParser.looksLikeSkippedSpeech(jsonData(["text": "Sin segmentos."])), "responses without segments are not flagged")
    }

    private static func jsonData(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            fatalError("Synthetic JSON fixture should be serializable")
        }
        return data
    }

    private static func expectInvalidResponse(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try TranscriptionResponseParser.parse(data)
            TestSupport.expect(false, "Expected invalid response error", file: file, line: line)
        } catch let error as TranscriptionResponseParsingError {
            TestSupport.expectEqual(error, .invalidResponse, file: file, line: line)
        } catch {
            TestSupport.expect(
                false,
                "Expected TranscriptionResponseParsingError, got \(error)",
                file: file,
                line: line
            )
        }
    }
}
