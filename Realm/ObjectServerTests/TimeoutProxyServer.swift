////////////////////////////////////////////////////////////////////////////
//
// Copyright 2020 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Foundation
import Network

@available(OSX 10.14, *)
@objc(TimeoutProxyServer)
public class TimeoutProxyServer: NSObject {
    let port: NWEndpoint.Port
    let targetPort: NWEndpoint.Port

    let queue = DispatchQueue(label: "TimeoutProxyServer")
    var listener: NWListener!
    var connections = [NWConnection]()

    let serverEndpoint = NWEndpoint.Host("127.0.0.1")

    @objc public var delay: Double = 0

    @objc public init(port: UInt16, targetPort: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.targetPort = NWEndpoint.Port(rawValue: targetPort)!
    }

    @objc public func start() throws {
        listener = try NWListener(using: NWParameters.tcp, on: port)
        listener.newConnectionHandler = { incomingConnection in
            self.connections.append(incomingConnection)
            incomingConnection.start(queue: self.queue)

            let targetConnection = NWConnection(host: self.serverEndpoint, port: self.targetPort, using: .tcp)
            targetConnection.start(queue: self.queue)
            self.connections.append(targetConnection)

            self.queue.asyncAfter(deadline: .now() + self.delay) {
                self.copy(from: incomingConnection, to: targetConnection)
                self.copy(from: targetConnection, to: incomingConnection)
            }
        }
        listener.start(queue: self.queue)
    }

    @objc public func stop() {
        for connection in connections {
            connection.forceCancel()
        }
        listener.cancel()
    }

    private func copy(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] (data, context, isComplete, _) in
            guard let data = data else {
                self?.copy(from: from, to: to)
                return
            }
            to.send(content: data, contentContext: context ?? .defaultMessage,
                    isComplete: isComplete, completion: .contentProcessed({ [weak self] _ in
                        self?.copy(from: from, to: to)
                    }))
        }
    }
}