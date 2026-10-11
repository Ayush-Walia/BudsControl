# CLAUDE.md

Guidance for AI assistants working on Buds Control, a macOS 26 background app that controls OnePlus Buds Pro 3 over Bluetooth. Read `README.md` for what it does and `docs/PROTOCOL.md` before touching anything that talks to the buds.

## Layout

| Path | Role |
|---|---|
| `App/AppDelegate.swift` | Entry point. Accessory app (no Dock icon), URL scheme handler, ⌥⌘B hotkey, Control Center reload on launch |
| `App/BudsConnection.swift` | IOBluetooth discovery, RFCOMM channel, retries, notification registration, packet handling |
| `App/BudsProtocol.swift` | Command ids, frame codec, payload parsers |
| `App/BudsStore.swift` | Observable state. Every change is saved to the App Group and reloads the control |
| `App/PanelController.swift`, `App/PanelView.swift` | Floating NSPanel and its SwiftUI content |
| `Widget/BudsControlWidget.swift` | WidgetKit `ControlWidget` (Control Center tile) |
| `Shared/SharedState.swift` | `NoiseMode`, `BudsSnapshot`, tile text, App Group store |
| `Shared/ShowPanelIntent.swift` | Intent the tile runs to open the panel |
| `project.yml` | XcodeGen definition. The `.xcodeproj` is generated and git-ignored |

## Build and run

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project BudsControl.xcodeproj -scheme BudsControl -configuration Debug \
  -derivedDataPath build -allowProvisioningUpdates build
pkill -f "Buds Control.app"
rm -rf ~/Applications/"Buds Control.app"
cp -R "build/Build/Products/Debug/Buds Control.app" ~/Applications/
open ~/Applications/"Buds Control.app"
```

- Kill the old app (which also matches the widget extension process) before copying. Otherwise Control Center may keep running the old widget binary.
- After changing anything the tile shows, the app reloads controls on launch. If the tile still looks old, remove it and add it back in Control Center.
- There are no unit tests yet. Verify against real buds.

## Debugging

- Logs use subsystem `com.ayushwalia.budscontrol` (categories `bt` and `intent`). Each received packet is logged at debug level.
- Debug messages are not persisted. Stream them:
  ```sh
  /usr/bin/log stream --style compact --level debug --predicate 'subsystem == "com.ayushwalia.budscontrol"'
  ```
- Use `/usr/bin/log`, since `log` may be shadowed by a shell function.
- Control Center action errors show up under `ControlCenter` and `chronod` in the unified log.

## Things that were learned the hard way

- **Mode bits:** the bits sent to set a mode differ from the bits reported back. See the table in `docs/PROTOCOL.md`. Do not "fix" `NoiseMode.setBit` or `init(reportedBitmap:)` to match each other.
- **Push events need registration.** Without `0x0200` then `0x0205` at connect time the buds send no `0x0204` events, and the UI only updates on the slow poll.
- **First RFCOMM open fails** on macOS after the buds connect. `openChannel` retries. Keep the retry.
- **Case battery** is only reported while a bud is docked with the lid open. The store keeps the last value and `caseSeen`.
- **Opening the panel from the tile:** intents with `supportedModes = .foreground` and `OpenURLIntent` chaining both failed with `LNActionExecutorErrorDomain` 2018. The working approach is the extension calling `NSWorkspace.shared.open(budscontrol://panel)`.
- **Panel closing instantly:** Control Center dismissing steals focus. The URL handler shows the panel after 0.3 s, and the panel ignores resign-key and outside clicks for its first 0.5 s.
- **Tile text** fits about two lines of 12 characters. Keep `controlTitle` and `controlSubtitle` short. Mode names on the tile are Normal, Ambient and ANC.

## Design decisions

- No menu bar icon. The owner's menu bar is full, so Control Center plus the floating panel is the only UI surface.
- Clicking the tile always opens the panel. It never switches modes directly.
- Event driven to keep energy use near zero. The 5 minute poll is only a safety net. Do not add frequent polling.
- New behaviour should not change how the buds behave unless the user asks for it.

## Signing

- The team ID and bundle identifiers are hard-coded in `project.yml`, both `.entitlements` files (via `project.yml`) and `SharedStore.groupID`. Change all of them together.
- macOS App Group IDs use the team-prefixed form (`<TEAM>.com.example.app`), which works without a provisioning profile.
