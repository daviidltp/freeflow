enum MicrophoneSelectionCoreTests {
    private typealias Core = MicrophoneSelectionCore

    static func run() {
        testTransportMapping()
        testLidClosedPrefersHeadsetAndSkipsAggregate()
        testLidOpenWithoutHeadsetUsesBuiltIn()
        testLidOpenPrefersBuiltInOverHeadset()
        testContinuityOnlyWhenNothingElse()
        testOnlyAggregateLeavesNothing()
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static let aggregate = Core.Candidate(uid: "~:Aggregate:0", name: "Aggregate", transport: .aggregate)
    private static let builtIn = Core.Candidate(uid: "BuiltIn", name: "MacBook Mic", transport: .builtIn)
    private static let phone = Core.Candidate(uid: "phone", name: "Phone Mic", transport: .continuity)
    private static let headset = Core.Candidate(uid: "headset", name: "Headset", transport: .bluetooth)
    private static let virtual = Core.Candidate(uid: "virtual", name: "Loopback", transport: .virtual)
    private static let display = Core.Candidate(uid: "display", name: "Display Mic", transport: .other)

    private static func testTransportMapping() {
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("bltn")), .builtIn)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("blue")), .bluetooth)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("blea")), .bluetooth)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("usb ")), .usb)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("ccwd")), .continuity)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("ccwl")), .continuity)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("grup")), .aggregate)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("virt")), .virtual)
        TestSupport.expectEqual(Core.transport(coreAudioTransportType: code("thun")), .other)
        TestSupport.expect(Core.isAutomatic("auto"), "auto is the automatic selection")
        TestSupport.expect(!Core.isAutomatic("default"), "default follows the system")
    }

    private static func testLidClosedPrefersHeadsetAndSkipsAggregate() {
        let order = Core.automaticOrder([aggregate, builtIn, phone, headset, virtual], isLidClosed: true)
        TestSupport.expectEqual(order.map(\.uid), ["headset", "phone", "BuiltIn"])
    }

    private static func testLidOpenWithoutHeadsetUsesBuiltIn() {
        let order = Core.automaticOrder([aggregate, phone, display, builtIn], isLidClosed: false)
        TestSupport.expectEqual(order.map(\.uid), ["BuiltIn", "display", "phone"])
    }

    private static func testLidOpenPrefersBuiltInOverHeadset() {
        // A Bluetooth headset takes about a second to start its microphone.
        let order = Core.automaticOrder([headset, phone, builtIn], isLidClosed: false)
        TestSupport.expectEqual(order.map(\.uid), ["BuiltIn", "headset", "phone"])
    }

    private static func testContinuityOnlyWhenNothingElse() {
        let order = Core.automaticOrder([phone, aggregate], isLidClosed: true)
        TestSupport.expectEqual(order.map(\.uid), ["phone"])
    }

    private static func testOnlyAggregateLeavesNothing() {
        TestSupport.expectEqual(Core.automaticOrder([aggregate, virtual], isLidClosed: false), [])
    }
}
