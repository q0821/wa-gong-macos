import Darwin
import Foundation

final class WaGongRefineXPCProcessLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private var activeConnectionIDs: Set<UUID> = []

    func registerConnection() -> UUID {
        let connectionID = UUID()
        lock.lock()
        activeConnectionIDs.insert(connectionID)
        lock.unlock()
        return connectionID
    }

    func finishConnection(_ connectionID: UUID) {
        lock.lock()
        activeConnectionIDs.remove(connectionID)
        guard activeConnectionIDs.isEmpty else {
            lock.unlock()
            return
        }

        exit(EXIT_SUCCESS)
    }
}

final class WaGongRefineXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let processLifecycle = WaGongRefineXPCProcessLifecycle()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        let connectionID = processLifecycle.registerConnection()
        let service = WaGongRefineXPCService()
        newConnection.exportedInterface = NSXPCInterface(
            with: WaGongRefineXPCProtocol.self
        )
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [processLifecycle] in
            Task(priority: .utility) {
                await service.connectionInvalidated()
                processLifecycle.finishConnection(connectionID)
            }
        }
        newConnection.resume()
        return true
    }
}

let delegate = WaGongRefineXPCListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
