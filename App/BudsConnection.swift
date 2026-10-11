import Foundation
import IOBluetooth
import os

/// Finds the paired OnePlus buds, keeps the vendor RFCOMM channel open and translates packets into store updates.
@MainActor
final class BudsConnection: NSObject {
    static let shared = BudsConnection()

    /// SDP service class of the vendor channel ("ELNK"), RFCOMM channel 15 on Buds Pro 3.
    private static let serviceUUID: [UInt8] = [0x00, 0x00, 0x07, 0x9A, 0xD1, 0x02, 0x11, 0xE1,
                                               0x9B, 0x23, 0x00, 0x02, 0x5B, 0x00, 0xA5, 0xA5]
    private static let fallbackChannelID: BluetoothRFCOMMChannelID = 15
    private static let maxOpenAttempts = 4

    private let log = Logger(subsystem: "com.ayushwalia.budscontrol", category: "bt")
    private let store = BudsStore.shared

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var codec = BudsFrameCodec()
    private var seq: UInt8 = 0
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var pollTimer: Timer?
    private var opening = false
    private var pendingEvents: [UInt8] = []

    func start() {
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
        for case let dev as IOBluetoothDevice in IOBluetoothDevice.pairedDevices() ?? [] {
            log.info("paired: \(dev.name ?? "?", privacy: .public) connected=\(dev.isConnected()) buds=\(self.isBuds(dev))")
            if dev.isConnected(), isBuds(dev) { attach(dev) }
        }
    }

    func setMode(_ mode: NoiseMode) {
        guard channel?.isOpen() == true else { return }
        store.pendingMode = mode
        send(BudsCommand.setNoiseReduction, [1, 1, mode.setBit])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.send(BudsCommand.getNoiseReduction, [1, 1])
        }
    }

    func refresh() {
        send(BudsCommand.getNoiseReduction, [1, 1])
        send(BudsCommand.getBattery, [])
        send(BudsCommand.getEarbudsStatus, [])
    }

    // MARK: - Device discovery

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device dev: IOBluetoothDevice) {
        guard isBuds(dev) else { return }
        // Give the headset profiles a moment to settle before opening our channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.attach(dev) }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device dev: IOBluetoothDevice) {
        guard dev.addressString == device?.addressString else { return }
        log.info("device disconnected")
        teardown()
    }

    private func isBuds(_ dev: IOBluetoothDevice) -> Bool {
        if serviceRecord(dev) != nil { return true }
        return dev.name?.hasPrefix("OnePlus Buds") == true
    }

    private func serviceRecord(_ dev: IOBluetoothDevice) -> IOBluetoothSDPServiceRecord? {
        let uuid = Self.serviceUUID.withUnsafeBytes {
            IOBluetoothSDPUUID(bytes: $0.baseAddress, length: Self.serviceUUID.count)
        }
        return dev.getServiceRecord(for: uuid)
    }

    private func attach(_ dev: IOBluetoothDevice) {
        guard channel?.isOpen() != true, !opening else { return }
        device = dev
        disconnectNotification?.unregister()
        disconnectNotification = dev.register(forDisconnectNotification: self,
                                              selector: #selector(deviceDisconnected(_:device:)))
        store.update { $0.name = dev.name ?? $0.name }
        openChannel(attempt: 0)
    }

    // MARK: - Channel

    private func openChannel(attempt: Int) {
        guard let dev = device, dev.isConnected() else { opening = false; return }
        opening = true
        var channelID = Self.fallbackChannelID
        if let record = serviceRecord(dev) {
            var id: BluetoothRFCOMMChannelID = 0
            if record.getRFCOMMChannelID(&id) == kIOReturnSuccess { channelID = id }
        }
        var ch: IOBluetoothRFCOMMChannel?
        let result = dev.openRFCOMMChannelSync(&ch, withChannelID: channelID, delegate: self)
        if result == kIOReturnSuccess, let ch, ch.isOpen() {
            log.info("channel \(channelID) open on attempt \(attempt)")
            channelOpened(ch)
            return
        }
        // macOS reliably fails the first open after the headset connects; retrying works.
        log.info("open attempt \(attempt) failed: \(String(format: "0x%08x", result))")
        guard attempt + 1 < Self.maxOpenAttempts else { opening = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.openChannel(attempt: attempt + 1)
        }
    }

    private func channelOpened(_ ch: IOBluetoothRFCOMMChannel) {
        opening = false
        channel = ch
        codec = BudsFrameCodec()
        store.update { $0.connected = true }
        // Buds only push battery/status/mode events after we subscribe to them.
        send(BudsCommand.getNotificationCapability, [])
        refresh()
        pollTimer?.invalidate()
        // Safety net only; the buds push changes once registered.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.send(BudsCommand.getBattery, [])
                self?.send(BudsCommand.getEarbudsStatus, [])
            }
        }
    }

    private func teardown() {
        pollTimer?.invalidate()
        pollTimer = nil
        channel?.close()
        channel = nil
        opening = false
        store.pendingMode = nil
        store.update { $0.connected = false }
    }

    private func send(_ cmd: UInt16, _ payload: [UInt8]) {
        guard let ch = channel, ch.isOpen() else { return }
        var bytes = BudsFrameCodec.encode(BudsPacket(cmd: cmd, seq: seq, payload: payload))
        seq &+= 1
        let result = bytes.withUnsafeMutableBytes { ch.writeSync($0.baseAddress, length: UInt16($0.count)) }
        if result != kIOReturnSuccess {
            log.error("write 0x\(String(cmd, radix: 16)) failed: \(result)")
        }
    }

    // MARK: - Packet handling

    private func handle(_ packet: BudsPacket) {
        let p = packet.payload[...]
        log.debug("rx 0x\(String(packet.cmd, radix: 16), privacy: .public) \(packet.payload.map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        switch packet.cmd {
        case BudsCommand.getBattery | BudsCommand.responseFlag:
            if p.first == 0, let b = BudsParser.batteries(p.dropFirst()) { apply(batteries: b) }
        case BudsCommand.getEarbudsStatus | BudsCommand.responseFlag:
            break
        case BudsCommand.getNotificationCapability | BudsCommand.responseFlag:
            guard p.first == 0, p.count >= 2 else { return }
            let events = Array(p.dropFirst(2).prefix(Int(p[p.startIndex + 1])))
            pendingEvents = events
            send(BudsCommand.registerNotificationMulti, [UInt8(events.count)] + events)
        case BudsCommand.registerNotificationMulti | BudsCommand.responseFlag:
            // Older firmware rejects the batch form; the app then registers events one by one.
            if p.first != 0 {
                for event in pendingEvents { send(BudsCommand.registerNotification, [event]) }
            }
            log.info("notification register status \(p.first ?? 0xFF) events \(self.pendingEvents)")
        case BudsCommand.getNoiseReduction | BudsCommand.responseFlag:
            if p.first == 0, let bitmap = BudsParser.modeBitmap(p.dropFirst()) { apply(modeBitmap: bitmap) }
        case BudsCommand.notification:
            guard let event = p.first else { return }
            let body = p.dropFirst()
            switch event {
            case 0x01:
                if let b = BudsParser.batteries(body) { apply(batteries: b) }
            case 0x03:
                if let bitmap = BudsParser.modeBitmap(body) { apply(modeBitmap: bitmap) }
            default:
                break
            }
        default:
            break
        }
    }

    private func apply(batteries: [BudsPart: BatteryLevel]) {
        store.update { snap in
            snap.left = batteries[.left] ?? snap.left
            snap.right = batteries[.right] ?? snap.right
            // The case only reports while a bud is docked; keep the last value and when we saw it.
            if let c = batteries[.chargingCase] {
                snap.caseBattery = c
                snap.caseSeen = Date()
            }
        }
    }

    private func apply(modeBitmap: Int) {
        guard let mode = NoiseMode(reportedBitmap: modeBitmap) else {
            log.info("unknown mode bitmap 0x\(String(modeBitmap, radix: 16))")
            return
        }
        store.pendingMode = nil
        store.update { $0.mode = mode }
    }
}

extension BudsConnection: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                       data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = [UInt8](UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        MainActor.assumeIsolated {
            for packet in codec.feed(bytes) { handle(packet) }
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            guard rfcommChannel === channel else { return }
            log.info("channel closed")
            teardown()
            // Channel dropped while the headset stays connected: try to get it back.
            if let dev = device, dev.isConnected() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.attach(dev) }
            }
        }
    }
}
