import AppKit
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @ObservedObject var store = BudsStore.shared
    var onSelect: (NoiseMode) -> Void

    private var snap: BudsSnapshot { store.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            batteries
            Divider()
            noiseControl
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text(snap.name).font(.headline)
            Spacer()
            Circle()
                .fill(snap.connected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(snap.connected ? "Connected" : "Not connected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var batteries: some View {
        HStack(alignment: .top, spacing: 0) {
            BatteryCell(title: "Left", symbols: ["airpod.left", "earbuds"], battery: snap.left, note: nil)
            BatteryCell(title: "Right", symbols: ["airpod.right", "earbuds"], battery: snap.right, note: nil)
            BatteryCell(title: "Case", symbols: ["airpods.chargingcase.fill", "earbuds.case.fill", "case.fill"],
                        battery: snap.caseBattery, note: caseNote)
        }
        .opacity(snap.connected ? 1 : 0.5)
    }

    private var caseNote: String? {
        guard let seen = snap.caseSeen else { return snap.caseBattery == nil ? "dock a bud" : nil }
        let mins = Int(Date().timeIntervalSince(seen) / 60)
        return mins < 1 ? "just now" : "seen \(RelativeDateTimeFormatter().localizedString(for: seen, relativeTo: Date()))"
    }

    private var noiseControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noise Control").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach([NoiseMode.off, .transparency, .anc]) { mode in
                    ModeButton(mode: mode,
                               selected: (store.pendingMode ?? snap.mode) == mode,
                               pending: store.pendingMode == mode && snap.mode != mode) {
                        onSelect(mode)
                    }
                }
            }
            .disabled(!snap.connected)
            .opacity(snap.connected ? 1 : 0.5)
        }
    }

    private var footer: some View {
        HStack {
            LaunchAtLoginToggle()
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

private struct BatteryCell: View {
    let title: String
    let symbols: [String]
    let battery: BatteryLevel?
    let note: String?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(battery?.level ?? 0) / 100)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: firstAvailableSymbol(symbols))
                    .font(.system(size: 16))
            }
            .frame(width: 44, height: 44)
            HStack(spacing: 2) {
                Text(battery.map { "\($0.level)%" } ?? "—").font(.callout.monospacedDigit())
                if battery?.charging == true {
                    Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green)
                }
            }
            Text(note ?? title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var ringColor: Color {
        guard let b = battery else { return .clear }
        if b.charging { return .green }
        return b.level <= 20 ? .red : .primary
    }
}

private struct ModeButton: View {
    let mode: NoiseMode
    let selected: Bool
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.accentColor : Color.secondary.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: firstAvailableSymbol(mode.symbolCandidates))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                    if pending {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(mode.shortTitle).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Start Buds Control at login", isOn: Binding(
            get: { enabled },
            set: { on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    NSLog("BudsControl: login item change failed: \(error)")
                }
                enabled = SMAppService.mainApp.status == .enabled
            }))
        .toggleStyle(.checkbox)
    }
}

func firstAvailableSymbol(_ names: [String]) -> String {
    names.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "circle"
}
