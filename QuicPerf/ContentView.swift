//
//  ContentView.swift
//  QuicPerf
//
//  Created by Thad House on 3/21/22.
//

import SwiftUI

import Network

protocol PerfConn {
    func Start() -> Void
    func Stop() -> Void
    func GetCount() -> UInt64
}



class NWPerfConn: PerfConn {
    func GetCount() -> UInt64 {
        return count
    }

    static func MakeNWParameters() -> NWParameters {
        let options = NWProtocolQUIC.Options(alpn: ["perf"])
        options.direction = .bidirectional
        let securityOptions: sec_protocol_options_t = options.securityProtocolOptions;
        sec_protocol_options_set_verify_block(securityOptions, {
            (_: sec_protocol_metadata_t, _: sec_trust_t, complete: @escaping sec_protocol_verify_complete_t) in
            complete(true)
        }, DispatchQueue.main)
        return NWParameters(quic: options)
    }

    let parameters = MakeNWParameters()

    let sendcomplete: NWConnection.SendCompletion = .contentProcessed({
        (error: Error?) in

    })

    let conn: NWConnection

    func send() {
        var data = Data()
        data.append(contentsOf: [255, 255, 255, 255, 255, 255, 255, 255])
        self.conn.send(content: data,
                        contentContext: .finalMessage,
                        isComplete: true,
                        completion: sendcomplete)
    }

    var count: UInt64 = 0

    func configureReceive() {
        self.conn.receive(minimumIncompleteLength: 1, maximumLength: 0xFFFFFF)
        { [weak self] completeContent, contentContext, isComplete, error in
            self?.count += UInt64(completeContent?.count ?? 0)
            self?.configureReceive()
        }
    }


    init(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        conn = NWConnection(host: host, port: port, using: parameters)
    }

    func Start() {
        configureReceive()
        conn.stateUpdateHandler = { [weak self]
            (state: NWConnection.State) in
            print("state: \(state)")
            switch state {
                case .ready:
                self?.send()
                    break;
                default:
                    break
            }
        }
        conn.start(queue: DispatchQueue.main)
    }

    func Stop() {
        conn.forceCancel()
    }
}

class MSQuicPerfConn: PerfConn {
    init(host: NWEndpoint.Host, port: NWEndpoint.Port) {
        if (QUIC_Initialize() == 0) {
            print("Quic Init Failed")
        }
    }

    func Start() {
        QUIC_Start();
    }

    func Stop() {
        QUIC_Stop()
    }

    func GetCount() -> UInt64 {
        return QUIC_GetCount()
    }


}

var pConn: PerfConn? = nil
var inittedTime = false

func PrintTime(self: ContentView) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.count = pConn?.GetCount() ?? 0;
        if (self.count == 0) {
            self.lastCount = 0
            PrintTime(self: self)
            return
        }
        self.delta = self.count - self.lastCount
        // TODO take timestamps into account
        self.deltaKbps = (self.delta / 100) * 8
        self.deltaMbps = (self.deltaKbps / 1000)
        self.lastCount = self.count
        PrintTime(self: self)
    }
}

struct ContentView: View {
    @State var count : UInt64 = 0;
    @State var lastCount: UInt64 = 0
    @State var delta: UInt64 = 0
    @State var deltaKbps: UInt64 = 0
    @State var deltaMbps: UInt64 = 0
    @State var useMsQuic = false
    var body: some View {
        VStack {
            Toggle("MsQuic?", isOn: $useMsQuic)
            Button("Start!") {
                if (!inittedTime) {
                    inittedTime = true
                    PrintTime(self: self)
                }
                if ((pConn) != nil) {
                    pConn!.Stop()
                    pConn = nil
                }
                self.count = 0;
                self.lastCount = 0;
                if (useMsQuic) {
                pConn = MSQuicPerfConn(host: "192.168.1.36", port: 4433)
                }
                else {
                    pConn = NWPerfConn(host: "192.168.1.36", port: 4433)
                }
                pConn!.Start()
            }
            Button("Stop!") {
                pConn!.Stop()
                pConn = nil
            }
            Text("Count \(count)")
            Text("Delta \(delta)")
            Text("Kbps \(deltaKbps)")
            Text("Mbps \(deltaMbps)")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
