import AppIntents
import SwiftUI
import WidgetKit

@main
struct BudsWidgetBundle: WidgetBundle {
    var body: some Widget {
        BudsPanelControl()
    }
}

/// Control Center tile: shows mode and battery, tap always opens the floating panel.
struct BudsPanelControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedStore.controlKind, provider: Provider()) { snap in
            ControlWidgetButton(action: ShowBudsPanelIntent()) {
                Label {
                    Text(snap.controlTitle)
                    Text(snap.controlSubtitle)
                } icon: {
                    Image(systemName: snap.controlSymbol)
                }
            }
        }
        .displayName("OnePlus Buds")
        .description("Battery and noise control for your OnePlus Buds.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: BudsSnapshot {
            BudsSnapshot(connected: true, left: .init(level: 100, charging: false),
                         right: .init(level: 100, charging: false), mode: .anc)
        }

        func currentValue() async throws -> BudsSnapshot {
            SharedStore.load()
        }
    }
}
