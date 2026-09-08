# 02 - Socket Protocols

Two binary framing protocols are used between the Electron UI and the native backends.

---

## Protocol A — Main Agent & Voice Sockets

Used by: `logitech_kiros_agent`, `logitech_kiros_logivoice`

### Wire Format (Sending)

```
Offset  Size     Endian   Field
──────  ──────   ──────   ─────
0       4 bytes  LE       inner_frame_size (= proto_name.length + payload.length + 8)
4       4 bytes  BE       proto_name_length
8       N bytes  ASCII    proto_name (always "json")
8+N     4 bytes  BE       payload_length
12+N    M bytes  UTF-8    JSON payload
```

### Pseudocode (Send)

```swift
func send(message: String, socket: Socket) {
    let payload = message.data(using: .utf8)!
    let protoName = "json".data(using: .ascii)!

    // inner_frame_size = proto_name_len_field(4) + proto_name + payload_len_field(4) + payload
    let innerSize = UInt32(protoName.count + payload.count + 8)

    var frame = Data()
    frame.append(innerSize.littleEndianBytes)        // 4 bytes LE
    frame.append(UInt32(protoName.count).bigEndianBytes)  // 4 bytes BE
    frame.append(protoName)                          // N bytes
    frame.append(UInt32(payload.count).bigEndianBytes)    // 4 bytes BE
    frame.append(payload)                            // M bytes

    socket.write(frame)
}
```

### Parsing State Machine (Receiving)

```
State: START
  Read: 4 bytes -> UInt32 BE (discarded/ignored preamble)
  -> PROTO_HEADER

State: PROTO_HEADER
  Read: 4 bytes -> UInt32 BE = proto_name_length
  -> PROTO_PAYLOAD

State: PROTO_PAYLOAD
  Read: proto_name_length bytes -> protocol name string
  -> MESSAGE_HEADER

State: MESSAGE_HEADER
  Read: 4 bytes -> UInt32 BE = payload_length
  -> PAYLOAD

State: PAYLOAD
  Read: payload_length bytes -> raw payload
  If protocol name == "json": emit message (parse as JSON)
  -> START
```

**Important**: Reading uses Big-Endian for the preamble/lengths, but sending uses Little-Endian for the first 4 bytes. This asymmetry is confirmed in the source.

---

## Protocol B — LogiConn (Plugin Service / CC Socket)

Used by: `LogiPluginService`

### Wire Format (Sending)

```
Offset      Size     Endian   Field
──────      ──────   ──────   ─────
0           4 bytes  LE       total_frame_length
4           8 bytes  -        magic: "LogiConn" (0x4C6F6769436F6E6E)
12          1 byte   -        version (0x01)
13          2 bytes  -        reserved (0x0000)
15          1 byte   -        channel_name_length
16          N bytes  ASCII    channel_name (e.g. "configui")
16+N        4 bytes  LE       payload_length
20+N        8 bytes  LE       header_fnv_hash
28+N        M bytes  UTF-8    JSON payload
28+N+M      8 bytes  LE       payload_fnv_hash
```

`total_frame_length` = everything after the first 4 bytes = `12 + 1 + N + 4 + 8 + M + 8`

### FNV Hash Function (Custom Variant)

```swift
func fnvHash(_ data: Data, offset: Int = 0, length: Int? = nil) -> UInt64 {
    let len = length ?? data.count
    var hash: UInt64 = 3_074_457_345_618_258_791  // offset basis
    let prime: UInt64 = 3_074_457_345_618_258_799

    for i in 0..<len {
        hash = hash &+ UInt64(data[offset + i])   // NOTE: addition, NOT XOR
        hash = hash &* prime                       // wrapping multiply (mod 2^64)
    }
    return hash
}
```

**Critical**: This differs from standard FNV-1a which uses XOR (`^`). Logitech uses addition (`+`).

### Pseudocode (Send)

```swift
func sendLogiConn(channel: String, message: Any, socket: Socket) {
    let payloadStr = (message is String) ? message as! String : jsonEncode(message)
    let payload = payloadStr.data(using: .utf8)!
    let channelData = channel.data(using: .ascii)!

    // Build header
    var header = Data()
    header.append(contentsOf: [0x4C,0x6F,0x67,0x69,0x43,0x6F,0x6E,0x6E]) // "LogiConn"
    header.append(0x01)                                   // version
    header.append(contentsOf: [0x00, 0x00])               // reserved
    header.append(UInt8(channelData.count))                // channel name length
    header.append(channelData)                             // channel name
    header.append(UInt32(payload.count).littleEndianBytes) // payload length LE

    // Hash header
    let headerHash = fnvHash(header)
    var headerHashBytes = Data(count: 8)
    headerHashBytes.withUnsafeMutableBytes { $0.storeBytes(of: headerHash.littleEndian, as: UInt64.self) }

    // Hash payload
    let payloadHash = fnvHash(payload)
    var payloadHashBytes = Data(count: 8)
    payloadHashBytes.withUnsafeMutableBytes { $0.storeBytes(of: payloadHash.littleEndian, as: UInt64.self) }

    // Assemble full frame
    var fullFrame = Data()
    fullFrame.append(header)
    fullFrame.append(headerHashBytes)
    fullFrame.append(payload)
    fullFrame.append(payloadHashBytes)

    // Prepend total length
    var wire = Data()
    wire.append(UInt32(fullFrame.count).littleEndianBytes)
    wire.append(fullFrame)

    socket.write(wire)
}
```

### Parsing State Machine (Receiving)

```
State: HEADER
  Need >= 16 bytes
  Validate bytes[4..11] == "LogiConn"
  Validate bytes[12] == 0x01 (version)
  channel_name_length = bytes[15]
  headerSize = 16 + channel_name_length

  Need >= headerSize + 4 (payload_len) + 8 (header_hash)
  payload_length = UInt32LE at offset [headerSize]
  -> PAYLOAD (consume headerSize + 4 + 8 bytes)

State: PAYLOAD
  Need >= payload_length + 8 (payload_hash)
  Read payload_length bytes as payload
  Read 8 bytes as stored_hash (UInt64LE)
  Compute actual_hash = fnvHash(payload)
  If actual_hash != stored_hash: discard, log warning
  Else: emit message
  -> HEADER
```

---

## JSON Message Envelope

Both protocols carry the same JSON message format:

```json
{
    "verb": "GET",
    "path": "/devices/list",
    "msgId": "unique-string-id",
    "payload": {}
}
```

### Verbs

| Verb | Usage |
|------|-------|
| `GET` | Query/read data |
| `SET` | Write/modify data |
| `EVENT` | Event notifications (server -> client) |
| `REMOVE` | Delete data |

**Note on SUBSCRIBE/UNSUBSCRIBE**: The agent internally rejects these verbs over the wire. Subscriptions are managed internally by the agent's `endpoint_base::register_subscription()`. The UI receives subscription events as `EVENT` verb messages pushed from the agent.

### Plugin Service Wrapping

Messages to the Plugin Service (CC) get wrapped with extra fields:

```json
{
    "id": 1,
    "name": "device-name",
    "messageType": "Request",
    "channelName": "configui",
    ...originalMessageFields
}
```

Responses include `channelName` for filtering (must match `"configui"`). Request-response correlation uses `"<name>-<id>"` or just `<id>` if `id === 0`.

---

## Connection Lifecycle

### Establishment

```
1. Compute socket path: "/tmp/logitech_kiros_agent-" + MD5(username)
2. Connect via Unix domain socket (net.createConnection)
3. On "connect": initialize protocol parser
4. On "ready": connection is live, start sending messages
5. On "data": feed to parser -> emit parsed JSON messages
```

### Reconnection (Exponential Backoff)

```
maxReconnectInterval = 30000 (30s)
reconnectInterval = 100 (main) or 2000 (voice/CC)
reconnectDecay = 1.5

On disconnect:
  reconnectAttempt++
  delay = min(reconnectInterval * reconnectAttempt * reconnectDecay, maxReconnectInterval)
  setTimeout(connect, delay)
```

### Typical Startup Sequence

```
1. Connect to socket
2. GET /routes                      -> Discover all available API routes
3. GET /system/info                 -> System information
4. GET /devices/list                -> Connected devices
5. GET /devices/{id}/info           -> Per-device details
6. GET /battery/{id}/state          -> Battery status
7. GET /v2/profiles/slice           -> User profiles & assignments
8. Subscribe to events (battery changes, device connect/disconnect, etc.)
```
