//  IPCServer.swift
//  A tiny newline-delimited JSON command server, ported from pop-maker-studio's
//  IPC (ipc_server.cpp): each message is a {id,method,params} envelope terminated
//  by '\n'; the reply is {id,result} or {id,error} + '\n'. Requests route straight
//  to the engine (pms_command), so every desktop lever + query works verbatim.
//  Bonjour-advertised (_pmsipc._tcp) so the Mac / a future agent can discover +
//  drive the app — live debugging aid now, agent control later.

import Foundation
import Network

final class IPCServer {
    static let shared = IPCServer()
    private var listener: NWListener?
    weak var engine: EngineStore?
    let port: UInt16 = 8765
    private(set) var address = "starting…"   // <ip>:<port>, shown in Settings for connecting

    func start(engine: EngineStore) {
        self.engine = engine
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { st in if case .failed(let e) = st { NSLog("[ipc] listener failed: \(e)") } }
            l.start(queue: .global(qos: .utility))
            listener = l
            address = "\(Self.wifiIP() ?? "?"):\(port)"
            NSLog("[ipc] listening on \(address)")
        } catch { NSLog("[ipc] start failed: \(error)") }
    }

    /// Best-effort Wi-Fi (en0) IPv4 so the Mac can connect without Bonjour.
    static func wifiIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if ifa.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: ifa.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ifa.ifa_addr, socklen_t(ifa.ifa_addr.pointee.sa_len),
                            &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                addr = String(cString: host)
            }
            ptr = ifa.ifa_next
        }
        freeifaddrs(ifaddr)
        return addr
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        receive(conn, buffer: Data())
    }

    // Read into a rolling buffer, dispatch each '\n'-terminated JSON line.
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            while let nl = buf.firstIndex(of: 0x0A) {
                let line = buf.subdata(in: buf.startIndex..<nl)
                buf.removeSubrange(buf.startIndex...nl)
                self.handle(line, conn)
            }
            if done || err != nil { conn.cancel() }
            else { self.receive(conn, buffer: buf) }
        }
    }

    private func handle(_ line: Data, _ conn: NWConnection) {
        guard let req = String(data: line, encoding: .utf8),
              !req.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Serialize with the app's own commands by running on the main thread.
        let reply = DispatchQueue.main.sync { self.engine?.rawCommand(req) ?? #"{"error":"no engine"}"# }
        var out = Data(reply.utf8); out.append(0x0A)
        conn.send(content: out, completion: .contentProcessed { _ in })
    }
}
