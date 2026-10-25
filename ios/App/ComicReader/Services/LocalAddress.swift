import Darwin
import Foundation

// MARK: - 本机局域网 IPv4
//
// 只用于在传输面板上拼出可访问地址。优先 Wi-Fi（en0），其次个人热点
// （bridge100），再退到任意非回环、非链路本地地址。

enum LocalAddress {
    static func primaryIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var candidates: [(name: String, ip: String)] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                let flags = Int32(interface.ifa_flags)
                if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let length = socklen_t(address.pointee.sa_len)
                    let result = getnameinfo(
                        address,
                        length,
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    if result == 0 {
                        let ip = host.withUnsafeBufferPointer { buffer -> String in
                            guard let base = buffer.baseAddress else { return "" }
                            return String(cString: base)
                        }
                        if !ip.isEmpty, ip != "0.0.0.0", !ip.hasPrefix("169.254.") {
                            candidates.append((String(cString: interface.ifa_name), ip))
                        }
                    }
                }
            }
            cursor = interface.ifa_next
        }

        for preferred in ["en0", "bridge100", "en1"] {
            if let hit = candidates.first(where: { $0.name == preferred }) {
                return hit.ip
            }
        }
        return candidates.first?.ip
    }
}
