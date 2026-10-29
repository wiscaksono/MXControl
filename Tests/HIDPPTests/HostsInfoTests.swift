import Testing
@testable import HIDPP

struct HostsInfoTests {
    @Test func readsFriendlyNameChunk() async throws {
        let mock = MockHIDTransport()
        var payload = [UInt8](repeating: 0, count: 16)
        payload[0] = 1
        payload[1] = 0
        let name = Array("MacBook Pro".utf8)
        for (index, byte) in name.enumerated() {
            payload[2 + index] = byte
        }
        mock.respond(featureIndex: 0x0B, functionId: 0x03, params: payload)

        let chunk = try await HostsInfoFeature.getHostFriendlyName(
            transport: mock,
            deviceIndex: 0x01,
            featureIndex: 0x0B,
            hostIndex: 1,
            offset: 0
        )

        #expect(mock.sentRequests[0].params == [1, 0, 0])
        #expect(Array(chunk.bytes.prefix(name.count)) == name)
    }

    @Test func enumerateUsesStoredNames() async throws {
        let mock = MockHIDTransport()

        var info = [UInt8](repeating: 0, count: 16)
        info[0] = 0x01 // GET_NAME
        info[2] = 2
        info[3] = 0
        mock.respond(featureIndex: 0x0B, functionId: 0x00, params: info)

        var slot0 = [UInt8](repeating: 0, count: 16)
        slot0[0] = 0
        slot0[1] = 1
        slot0[2] = 2
        slot0[4] = 11
        slot0[5] = 14
        mock.respond(featureIndex: 0x0B, functionId: 0x01, params: slot0)

        var slot1 = [UInt8](repeating: 0, count: 16)
        slot1[0] = 1
        slot1[1] = 0
        slot1[2] = 0
        mock.respond(featureIndex: 0x0B, functionId: 0x01, params: slot1)

        var name = [UInt8](repeating: 0, count: 16)
        name[0] = 0
        name[1] = 0
        for (index, byte) in Array("MacBook Pro".utf8).enumerated() {
            name[2 + index] = byte
        }
        mock.respond(featureIndex: 0x0B, functionId: 0x03, params: name)

        let (hosts, current) = try await HostsInfoFeature.enumerateHosts(
            transport: mock,
            deviceIndex: 0x01,
            featureIndex: 0x0B
        )

        #expect(hosts.count == 2)
        #expect(hosts[0].name == "MacBook Pro")
        #expect(hosts[0].busType == .usb)
        #expect(hosts[1].name == "Host 2")
        #expect(current == 0)
    }
}
