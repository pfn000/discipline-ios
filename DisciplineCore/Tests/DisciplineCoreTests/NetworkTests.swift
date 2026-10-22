import XCTest
@testable import DisciplineCore

final class NetworkTests: XCTestCase {
    func testIPv4ParseAndFormat() {
        XCTAssertEqual(IPv4Address("10.7.0.1")?.description, "10.7.0.1")
        XCTAssertEqual(IPv4Address("255.255.255.255")?.value, UInt32.max)
        XCTAssertNil(IPv4Address("256.1.1.1"))
        XCTAssertNil(IPv4Address("1.2.3"))
        XCTAssertNil(IPv4Address("1.2.3.4.5"))
        XCTAssertNil(IPv4Address("a.b.c.d"))
        XCTAssertNil(IPv4Address("1..2.3"))
        XCTAssertNil(IPv4Address("+1.2.3.4"))
    }

    func testCIDRMath() throws {
        let c = try XCTUnwrap(IPv4CIDR("192.168.1.23/24"))
        XCTAssertEqual(c.network.description, "192.168.1.0")
        XCTAssertEqual(c.broadcast.description, "192.168.1.255")
        XCTAssertEqual(c.netmask.description, "255.255.255.0")
        XCTAssertTrue(c.contains(IPv4Address("192.168.1.200")!))
        XCTAssertFalse(c.contains(IPv4Address("192.168.2.1")!))
        XCTAssertEqual(c.usableHostCount, 254)
        XCTAssertEqual(IPv4CIDR("10.7.0.1")?.prefix, 32)
        XCTAssertNil(IPv4CIDR("10.0.0.1/33"))
        let fromMask = try XCTUnwrap(IPv4CIDR(address: IPv4Address("10.0.5.9")!, netmask: IPv4Address("255.255.252.0")!))
        XCTAssertEqual(fromMask.prefix, 22)
        XCTAssertNil(IPv4CIDR(address: IPv4Address("10.0.5.9")!, netmask: IPv4Address("255.0.255.0")!))
    }

    // A real IPv4+TCP SYN header from 10.7.1.1 to 10.7.0.1:62078 (lockdownd's port).
    private func samplePacket() -> [UInt8] {
        var p: [UInt8] = [0x45, 0x00, 0x00, 0x28, 0x1c, 0x46, 0x40, 0x00, 0x40, 0x06, 0x00, 0x00,
                          10, 7, 1, 1, 10, 7, 0, 1,
                          0xc3, 0x50, 0xf2, 0x7e, 0, 0, 0, 1, 0, 0, 0, 0, 0x50, 0x02, 0xff, 0xff, 0, 0, 0, 0]
        let csum = PacketReflector.headerChecksum(p[0..<20])
        p[10] = UInt8(csum >> 8); p[11] = UInt8(csum & 0xff)
        return p
    }

    func testReflectSwapsAddressesAndKeepsChecksumValid() {
        var p = samplePacket()
        XCTAssertEqual(PacketReflector.headerChecksum(p[0..<20]), 0, "sample starts valid")
        let original = p
        XCTAssertEqual(PacketReflector.reflect(&p), .reflected)
        XCTAssertEqual(Array(p[12..<16]), [10, 7, 0, 1])
        XCTAssertEqual(Array(p[16..<20]), [10, 7, 1, 1])
        XCTAssertEqual(PacketReflector.headerChecksum(p[0..<20]), 0, "checksum still valid after swap")
        XCTAssertEqual(Array(p[20...]), Array(original[20...]), "payload untouched")
        PacketReflector.reflect(&p)
        XCTAssertEqual(p, original, "reflecting twice restores the packet")
    }

    func testReflectSkipsNonIPv4AndShortPackets() {
        var v6 = [UInt8](repeating: 0, count: 40); v6[0] = 0x60
        XCTAssertEqual(PacketReflector.reflect(&v6), .skippedNotIPv4)
        var short = [UInt8](repeating: 0x45, count: 10)
        XCTAssertEqual(PacketReflector.reflect(&short), .skippedTooShort)
        var badIHL = samplePacket(); badIHL[0] = 0x4F // IHL 60 bytes > 40-byte packet
        XCTAssertEqual(PacketReflector.reflect(&badIHL), .skippedBadHeaderLength)
        let (d, o) = PacketReflector.reflected(Data(samplePacket()))
        XCTAssertEqual(o, .reflected); XCTAssertEqual(d[12], 10); XCTAssertEqual(d[14], 0)
    }

    func testPeerPlannerLegacyBefore26_4() throws {
        let plan = try PeerAddressPlanner().plan(wifi: IPv4CIDR("192.168.1.23/24"), iosMajor: 26, iosMinor: 3)
        XCTAssertEqual(plan.peerAddress.description, "10.7.0.1")
        XCTAssertFalse(plan.insideWiFiSubnet)
    }

    func testPeerPlannerInSubnetFrom26_4() throws {
        let wifi = IPv4CIDR("192.168.1.23/24")!
        let plan = try PeerAddressPlanner().plan(wifi: wifi, taken: [IPv4Address("192.168.1.254")!], iosMajor: 27, iosMinor: 2)
        XCTAssertTrue(plan.insideWiFiSubnet)
        XCTAssertEqual(plan.peerAddress.description, "192.168.1.253")
        XCTAssertEqual(plan.interfaceAddress.description, "192.168.1.252")
        XCTAssertTrue(wifi.contains(plan.peerAddress))
        XCTAssertNotEqual(plan.peerAddress, wifi.address)
        XCTAssertEqual(plan.peerPrefix, 32)
    }

    func testPeerPlannerNoWifiAndTinySubnets() throws {
        let off = try PeerAddressPlanner().plan(wifi: nil, iosMajor: 27, iosMinor: 2)
        XCTAssertEqual(off.peerAddress, PeerAddressPlanner.legacyPeer)
        XCTAssertThrowsError(try PeerAddressPlanner().plan(wifi: IPv4CIDR("10.0.0.1/31"), iosMajor: 27, iosMinor: 0)) {
            XCTAssertEqual($0 as? PeerAddressPlanner.PlanError, .subnetTooSmall)
        }
        // /30: hosts .1 and .2; phone is .1 → peer .2, interface falls back.
        let p = try PeerAddressPlanner().plan(wifi: IPv4CIDR("10.0.0.1/30"), iosMajor: 27, iosMinor: 0)
        XCTAssertEqual(p.peerAddress.description, "10.0.0.2")
        XCTAssertThrowsError(try PeerAddressPlanner().plan(wifi: IPv4CIDR("10.0.0.1/30"), taken: [IPv4Address("10.0.0.2")!], iosMajor: 27, iosMinor: 0))
    }

    func testTunnelDetector() {
        let en0 = InterfaceAddress(name: "en0", address: IPv4Address("192.168.1.23")!, netmask: IPv4Address("255.255.255.0")!)
        XCTAssertEqual(TunnelDetector.state(of: [en0]), .notConnected)
        let legacy = InterfaceAddress(name: "utun5", address: IPv4Address("10.7.1.1")!, netmask: nil)
        XCTAssertEqual(TunnelDetector.state(of: [en0, legacy]), .connected(interface: "utun5", address: IPv4Address("10.7.1.1")!))
        let down = InterfaceAddress(name: "utun5", address: IPv4Address("10.7.1.1")!, netmask: nil, isUp: false)
        XCTAssertEqual(TunnelDetector.state(of: [en0, down]), .notConnected)
        let inSubnet = InterfaceAddress(name: "utun6", address: IPv4Address("192.168.1.252")!, netmask: nil)
        XCTAssertEqual(TunnelDetector.state(of: [en0, inSubnet]), .connected(interface: "utun6", address: IPv4Address("192.168.1.252")!))
        let other = InterfaceAddress(name: "utun2", address: IPv4Address("172.16.0.2")!, netmask: nil)
        XCTAssertEqual(TunnelDetector.state(of: [en0, other]), .notConnected)
        XCTAssertEqual(TunnelDetector.state(of: [en0, other], expected: IPv4Address("172.16.0.2")), .connected(interface: "utun2", address: IPv4Address("172.16.0.2")!))
        XCTAssertEqual(TunnelDetector.wifi(in: [en0])?.prefix, 24)
    }
}
