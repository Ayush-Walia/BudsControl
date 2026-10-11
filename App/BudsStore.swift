import Foundation
import WidgetKit

/// App-wide observable state. Mirrors every change into the App Group so the Control Center tile can render it.
@MainActor
final class BudsStore: ObservableObject {
    static let shared = BudsStore()

    @Published private(set) var snapshot: BudsSnapshot
    @Published var pendingMode: NoiseMode?

    private init() {
        var snap = SharedStore.load()
        snap.connected = false
        snapshot = snap
    }

    func update(_ change: (inout BudsSnapshot) -> Void) {
        var next = snapshot
        change(&next)
        guard next != snapshot else { return }
        snapshot = next
        SharedStore.save(next)
        ControlCenter.shared.reloadControls(ofKind: SharedStore.controlKind)
    }
}
