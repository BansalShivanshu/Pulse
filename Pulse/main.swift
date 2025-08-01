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
    private var isCurrentlyOnline: Bool?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handleNetworkChange(path: path)
        }
        monitor.start(queue: queue)
    }

    private func handleNetworkChange(path: NWPath) {
        let isOnline = (path.status == .satisfied) && !path.isConstrained

        // If status hasn't changed, do nothing
        guard isOnline != isCurrentlyOnline else { return }
        isCurrentlyOnline = isOnline

        if isOnline {
            sendNotification(
                title: "Network Status",
                message: "✅ You're back online!",
                sound: "Glass"
            )
        } else {
            sendNotification(
                title: "Network Status",
                message: "⚠️ You went offline!",
                sound: "Funk"
            )
        }
    }

    private func sendNotification(title: String, message: String, sound: String? = nil) {
//        Using AppleScript for macOS Notification Center
        var script = "display notification \"\(message)\" with title \"\(title)\""
        if let sound = sound {
            script += " sound name \"\(sound)\""
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

// Start a lightweight daemon
let monitor = Pulse()
RunLoop.main.run()
