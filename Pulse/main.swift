//
//  main.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-07-31.
//

import Foundation
import Network

class Pulse {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)
    private var lastStatus: NWPath.Status?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkChange(status: path.status)
        }
        monitor.start(queue: queue)
    }

    private func handleNetworkChange(status: NWPath.Status) {
        if status != lastStatus {
            lastStatus = status
            switch status {
            case .satisfied:
                sendNotification(
                    title: "Network Status",
                    message: "✅ You are back online!",
                    sound: true
                )
            case .unsatisfied:
                sendNotification(
                    title: "Network Status",
                    message: "❌ You went offline!",
                    sound: true
                )
            default:
                break
            }
        }
    }

    private func sendNotification(title: String, message: String, sound: Bool = false) {
//        Using AppleScript for macOS Notification Center
        var script = "display notification \"\(message)\" with title \"\(title)\""
        if sound {
            script += " sound name \"Blow\""
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

let monitor = Pulse()
RunLoop.main.run()
