# Buds Control

A small macOS app that gives OnePlus Buds Pro 3 some of the Mac integration AirPods get: battery for each bud and the case, charging state, and one-click switching between Normal, Transparency and Noise Cancellation.

It runs in the background with no Dock or menu bar icon. You use it from a Control Center tile, which shows the current mode and battery and opens a floating panel when clicked.

> Not affiliated with, endorsed by, or connected to OnePlus or OPPO. "OnePlus" is a trademark of its owner. This is an independent project that talks to the buds over Bluetooth for interoperability.

## Features

- **Control Center tile**: shows the noise mode as its title (Normal, Ambient, ANC) and a compact battery line such as `100% · C80` or `⚡ L90 R100 · C80`. Clicking it opens the panel.
- **Floating panel**: battery rings for left, right and case, a charging bolt, and three buttons for the noise modes. It updates live from events the buds push.
- **Case battery memory**: the buds only report the case level while a bud is docked. The app keeps the last value and shows when it was read.
- **Keyboard shortcut**: ⌥⌘B toggles the panel from anywhere.
- **Auto-connect**: the app notices when the buds connect and opens its channel automatically.
- **Start at login** option in the panel.
- **Low energy use**: event driven. It idles at 0% CPU with no wakeups and polls only every 5 minutes as a safety net.

## Requirements

- macOS 26 (Tahoe) or newer. Control Center controls for third-party apps need macOS 26.
- OnePlus Buds Pro 3, paired with the Mac. Other OnePlus or OPPO buds may work, but the noise mode bits are only verified on the Buds Pro 3.
- To build: Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Install

Prebuilt releases are for Apple silicon Macs on macOS 26 or newer.

1. Download the latest `BudsControl-<version>-arm64.zip` from [Releases](https://github.com/Ayush-Walia/BudsControl/releases/latest).
2. Double-click the zip to extract **Buds Control.app**, then move it to your **Applications** folder.
3. Open it. macOS blocks it the first time because the app is not notarized by Apple. To allow it:
   - Open **System Settings › Privacy & Security**, scroll to the message about "Buds Control", click **Open Anyway**, and confirm.
   - Or run this in Terminal once:
     ```sh
     xattr -dr com.apple.quarantine "/Applications/Buds Control.app"
     ```
4. Allow Bluetooth access when macOS asks. If macOS asks whether Buds Control may access data from other apps, allow it. That is how the Control Center tile reads the app's state.
5. Add the tile: open Control Center, choose **Edit Controls**, and drag **OnePlus Buds** in. Right-click it in edit mode to pick the wider size, which shows the battery text.
6. Optional: open the panel and tick **Start Buds Control at login**.

Nothing appears in the Dock or menu bar. That is expected. Use the tile or ⌥⌘B.

## Build from source

1. Install XcodeGen:
   ```sh
   brew install xcodegen
   ```
2. Set your own Apple team ID. A free Personal Team works for running on your own Mac. Replace `7V2FXK5C22` in these places:
   - `project.yml` (`DEVELOPMENT_TEAM` and both `application-groups` entries)
   - `Shared/SharedState.swift` (`SharedStore.groupID`)

   If you fork, also change the `com.ayushwalia` bundle identifiers in `project.yml`.
3. Generate the project and build:
   ```sh
   xcodegen generate
   xcodebuild -project BudsControl.xcodeproj -scheme BudsControl -configuration Release \
     -derivedDataPath build -allowProvisioningUpdates build
   ```
   If `xcode-select` still points at the Command Line Tools, prefix the command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
4. Install and launch:
   ```sh
   cp -R "build/Build/Products/Release/Buds Control.app" ~/Applications/
   open ~/Applications/"Buds Control.app"
   ```
5. Allow Bluetooth access when macOS asks.
6. Add the tile: open Control Center, choose **Edit Controls**, and drag **OnePlus Buds** in. Right-click it in edit mode to pick the wider size, which shows the battery text.

## Using it

- Click the tile, or press ⌥⌘B, to open the panel. Click outside it or press Esc to close it.
- Pick a mode in the panel. The highlight moves once the buds confirm the change.
- To get a case reading, open the case with a bud inside. The app reads it within a few seconds of the buds connecting.

Some behaviour comes from the buds' firmware, not the app:

- Docking a bud switches noise control to Normal. Taking it out restores your previous mode.
- Closing the lid disconnects the buds after a few seconds, and the tile then shows "Not connected".

## Limitations

- ANC strength levels are not exposed yet.
- Multipoint device switching ("use on this Mac") is not implemented. The commands exist in the protocol but are not decoded.
- The tile can only show text and an SF Symbol. Battery details live in the panel.
- Only one program can hold the buds' control channel at a time.

## How it works

The app opens the buds' vendor RFCOMM channel through IOBluetooth and speaks the same protocol as the official HeyMelody Android app. The protocol is documented in [docs/PROTOCOL.md](docs/PROTOCOL.md).

| Path | Contents |
|---|---|
| `App/` | Background agent: Bluetooth connection, protocol codec, state store, floating panel, shortcut |
| `Widget/` | WidgetKit extension with the Control Center control |
| `Shared/` | State snapshot shared through an App Group, and the intent the tile runs |
| `project.yml` | XcodeGen project definition |
