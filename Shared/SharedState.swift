import Foundation

enum NoiseMode: String, Codable, CaseIterable, Identifiable {
    case off, transparency, anc

    var id: String { rawValue }

    /// Bit sent in the 0x0404 set-mode bitmap (verified on Buds Pro 3).
    var setBit: UInt8 {
        switch self {
        case .off: return 0x01
        case .anc: return 0x02
        case .transparency: return 0x04
        }
    }

    /// The buds report modes with different bits than the ones used to set them.
    init?(reportedBitmap: Int) {
        switch reportedBitmap {
        case 0x08: self = .off
        case 0x10: self = .anc
        case 0x100: self = .transparency
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .off: return "Normal"
        case .transparency: return "Transparency"
        case .anc: return "Noise Cancellation"
        }
    }

    /// Control Center tile title; the tile fits about 12 characters per line.
    var tileTitle: String {
        switch self {
        case .off: return "Normal"
        case .transparency: return "Ambient"
        case .anc: return "ANC"
        }
    }

    var shortTitle: String {
        switch self {
        case .off: return "Normal"
        case .transparency: return "Transparency"
        case .anc: return "ANC"
        }
    }

    var symbolCandidates: [String] {
        switch self {
        case .off: return ["person.fill", "circle"]
        case .transparency: return ["person.wave.2.fill", "ear"]
        case .anc: return ["person.crop.circle.badge.minus", "waveform.circle.fill"]
        }
    }
}

struct BatteryLevel: Codable, Equatable {
    var level: Int
    var charging: Bool
}

struct BudsSnapshot: Codable, Equatable {
    var connected = false
    var name = "OnePlus Buds"
    var left: BatteryLevel?
    var right: BatteryLevel?
    var caseBattery: BatteryLevel?
    var caseSeen: Date?
    var mode: NoiseMode?

    var controlTitle: String {
        guard connected else { return "Buds" }
        return mode?.tileTitle ?? "Buds"
    }

    /// The tile wraps to about two short lines, so keep this compact: equal buds merge into one level,
    /// a single leading ⚡ marks a charging bud, and the case keeps its own ⚡ for the case charging itself.
    var controlSubtitle: String {
        guard connected else { return "Not connected" }
        let caseText = caseBattery.map { "C\($0.level)\($0.charging ? "⚡" : "")" }
        let budsText: String?
        if left?.charging == true, right?.charging == true {
            budsText = "In case"
        } else if let l = left, let r = right {
            let levels = l.level == r.level ? "\(l.level)%" : "L\(l.level) R\(r.level)"
            budsText = (l.charging || r.charging ? "⚡ " : "") + levels
        } else {
            budsText = (left ?? right).map { "\($0.level)%" }
        }
        let parts = [budsText, caseText].compactMap { $0 }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }

    var controlSymbol: String { "earbuds" }
}

enum SharedStore {
    static let groupID = "7V2FXK5C22.com.ayushwalia.budscontrol"
    static let controlKind = "com.ayushwalia.budscontrol.panel"
    private static let key = "snapshot"

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func save(_ snapshot: BudsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> BudsSnapshot {
        guard let data = defaults?.data(forKey: key),
              let snap = try? JSONDecoder().decode(BudsSnapshot.self, from: data) else {
            return BudsSnapshot()
        }
        return snap
    }
}
