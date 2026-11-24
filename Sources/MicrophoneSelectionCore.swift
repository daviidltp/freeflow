/// Picks microphones for the «Automático» setting without touching AVFoundation,
/// so the ranking can be tested with synthetic devices.
enum MicrophoneSelectionCore {
    /// Stored in `selected_microphone_id` for the automatic choice.
    static let automaticID = "auto"
    /// Stored in `selected_microphone_id` for "follow the macOS input device".
    static let systemDefaultID = "default"

    enum Transport: Equatable {
        case builtIn
        case bluetooth
        case usb
        case continuity
        case aggregate
        case virtual
        case other
    }

    struct Candidate: Equatable {
        let uid: String
        let name: String
        let transport: Transport
    }

    static func isAutomatic(_ selectionID: String) -> Bool {
        selectionID == automaticID
    }

    /// Maps a CoreAudio `kAudioDevicePropertyTransportType` value.
    static func transport(coreAudioTransportType value: UInt32) -> Transport {
        switch value {
        case fourCC("bltn"):
            return .builtIn
        case fourCC("blue"), fourCC("blea"):
            return .bluetooth
        case fourCC("usb "):
            return .usb
        case fourCC("ccwd"), fourCC("ccwl"):
            return .continuity
        case fourCC("grup"), fourCC("fgrp"):
            return .aggregate
        case fourCC("virt"):
            return .virtual
        default:
            return .other
        }
    }

    /// Order in which «Automático» tries microphones: headsets first, then the
    /// MacBook microphone while the lid is open, then anything else, then the
    /// iPhone through Continuity. Aggregate and virtual devices are never used.
    /// The built-in microphone stays as a last resort with the lid closed,
    /// because macOS still lists it but it only delivers silence.
    static func automaticOrder(_ candidates: [Candidate], isLidClosed: Bool) -> [Candidate] {
        candidates.enumerated()
            .compactMap { index, candidate -> (rank: Int, index: Int, candidate: Candidate)? in
                guard let rank = rank(candidate.transport, isLidClosed: isLidClosed) else { return nil }
                return (rank, index, candidate)
            }
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.index < rhs.index
            }
            .map(\.candidate)
    }

    private static func rank(_ transport: Transport, isLidClosed: Bool) -> Int? {
        switch transport {
        case .bluetooth, .usb:
            return 0
        case .builtIn:
            return isLidClosed ? 4 : 1
        case .other:
            return 2
        case .continuity:
            return 3
        case .aggregate, .virtual:
            return nil
        }
    }

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
