# OnePlus Buds control protocol

This documents the protocol the official HeyMelody Android app uses to control OnePlus and OPPO earbuds, as far as Buds Control uses it. It was worked out by reading the app's decompiled code and then checked against a real OnePlus Buds Pro 3.

Everything marked **verified** was tested live on a Buds Pro 3. Anything else comes from the app's code only.

## Transport

| Transport | Identifier | Notes |
|---|---|---|
| Classic Bluetooth RFCOMM | SDP service `0000079A-D102-11E1-9B23-00025B00A5A5`, named `ELNK` | **Verified.** RFCOMM channel 15 on Buds Pro 3. Read the channel from SDP rather than hard-coding it. |
| BLE GATT | service `0000079A-D102-11E1-9B23-00025B00A5A5`, write characteristic `0100079A-…`, likely notify `0200079A-…` | Not used by Buds Control. |
| Classic RFCOMM (older models) | `00001107-D102-11E1-9B23-00025B00A5A5` | Not present on Buds Pro 3. |
| BLE advertising | service UUID `0x9801` | Not decoded. |

On macOS the first attempt to open the RFCOMM channel after the buds connect fails with `kIOReturnError` (`0xE00002BC`). The second attempt, about a second later, succeeds.

There is no encryption, authentication or checksum.

## Framing

All multi-byte integers are little-endian.

### Outer frame

```
AA | length (varint) | frameType | 00 | [fsn] | chunk
```

| Field | Meaning |
|---|---|
| `AA` | Start byte |
| length | Varint, 7 bits per byte, high bit set on all but the last byte. Counts every byte after itself. |
| frameType | `0` single, `1` first, `2` middle, `3` last |
| `00` | Reserved |
| fsn | Frame sequence number. Present only when frameType is not `0`. |
| chunk | A piece of the inner packet |

Packets are split across frames when they exceed the device's frame size (about 660 bytes by default). Every packet Buds Control sends fits in one frame. Several frames can arrive in a single RFCOMM read.

### Inner packet

```
cmd (u16) | seq (u8) | payloadLength (u16) | payload
```

- `seq` is a per-connection counter that wraps at 255.
- Responses use `cmd | 0x8000`.
- The first payload byte of a response is a status byte. `00` means success.

Example, get the current noise mode:

```
AA 09 00 00 | 0C 01 00 02 00 | 01 01
outer         cmd=0x010C seq=0 len=2   payload
```

## Commands

| Cmd | Name in the app | Request payload | Response |
|---|---|---|---|
| `0x0106` | getBatteryLevel | empty | `0x8106`: status, battery list. **Verified.** |
| `0x0109` | getEarBudsStatus | empty | `0x8109`: status, status list. **Verified.** |
| `0x010C` | get noise reduction info | `[action, type]`, see below | `0x810C`: status, action, data. **Verified** for `[1,1]`. |
| `0x0404` | setCurrentNoiseReduction | `[1, 1, bitmap]` | `0x8404`: status. **Verified.** |
| `0x0200` | get notification capability | empty | `0x8200`: status, count, event ids. **Verified.** |
| `0x0201` | register notification | `[eventId]` | `0x8201` |
| `0x0205` | register notifications (batch) | `[count, eventIds…]` | `0x8205`: status, count, (event, result) pairs. **Verified.** |
| `0x0204` | notification | sent by the buds | see Events |
| `0x0112` | getMultiConnectInformation | not decoded | |
| `0x0132` | getMultiConnectPriorityDevice | not decoded | |
| `0x0429` | operateMultiConnectHandheldDevice | not decoded | |

### Noise control

Get requests for `0x010C`:

| Payload | Returns |
|---|---|
| `[1, 1]` | Current mode bitmap |
| `[2, 1]` | Supported modes mask. Buds Pro 3 returned `0x0006`. |
| `[3, 1]` | Switch mode |
| `[4, 1]` | Intelligent (adaptive) mode. Buds Pro 3 returned `0x20`. |

The current mode comes back as `[status, 1, 1, bitmap LE…]`.

**The bits used to set a mode differ from the bits the buds report.** Verified on Buds Pro 3:

| Mode | Set bit (`0x0404`) | Reported bitmap |
|---|---|---|
| Normal (noise control off) | `0x01` | `0x0008` |
| Noise Cancellation | `0x02` | `0x0010` |
| Transparency | `0x04` | `0x0100` |

The official app does not hard-code these. It reads a per-model `protocolIndex` from cloud configuration, so other models may differ.

`0x0404` also accepts `[1, 2, level]` to set a level, and `[2, type, value…]` to set the supported-modes mask. Neither is used by Buds Control.

### Battery

Payload after the status byte:

```
count | (part, value) × count
```

| Part | Meaning |
|---|---|
| `1` | Left bud |
| `2` | Right bud |
| `3` | Case |

`value` bits 0 to 6 are the level in percent. Bit 7 (`0x80`) is set while that part is charging. For example `0xE4` is 100% and charging, and `0xD0` is the case at 80% and charging.

The case is only included while at least one bud is docked in it with the lid open. With both buds out, replies contain left and right only.

The official app rounds levels up to a per-model step (`batteryRadix`) before display.

### Earbud status

Same layout as battery, `count | (part, state) × count`. Observed values for the buds, verified:

| State | Meaning |
|---|---|
| `00` | In the case, lid closed |
| `04` | In the case, lid open |
| `05` | Out of the case, not worn |
| `07` | In ear |

The case entry was always `04` in testing and does not reflect the lid or charging.

## Events

The buds send `0x0204` notifications only after the host registers for them:

1. Send `0x0200`. Buds Pro 3 replied with nine event ids: `01 02 03 04 08 0B F1 F2 F3`.
2. Send `0x0205` with `[count, ids…]`. The reply lists a result per event. Buds Pro 3 returned `00` for some and `02` for others, and pushes worked for battery, status and mode.
3. If the batch form fails, the official app falls back to sending `0x0201` once per event.

Without registration no events arrive. It may look like they do if the phone app registered earlier in the same session.

Notification payload: `eventId | body`.

| Event | Body | Notes |
|---|---|---|
| `01` | Battery list, same layout as `0x8106` without the status byte | **Verified** |
| `02` | Earbud status list | **Verified** |
| `03` | `[1, 1, bitmap…]` current noise mode | **Verified.** Also sent when the firmware changes mode by itself. |
| `04` | Intelligent noise mode | From code |
| `F1` | Unknown. Seen once as `F1 01 01 07 0B 03` while handling a bud. | Not decoded |
| `08`, `0B`, `F2`, `F3` | Unknown | Not decoded |

## Firmware behaviour

Verified on Buds Pro 3:

- Docking a bud switches noise control to Normal and sends event `03`. Putting the bud back in the ear restores the previous mode.
- Closing the lid with both buds inside disconnects them from the host after a few seconds.
- Audio keeps playing while the RFCOMM channel is open.
