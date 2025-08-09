//
//  main.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-07-31.
//

import Foundation
import Network

final class Pulse {
    private let watcher = WiFiConnectivityWatcher()

    init() {
        watcher.onChange = { [weak self] state in
            switch state {
            case .online:
                self?.notify(title: "Network Status", message: "✅ Internet is available", sound: "Glass")
            case .wifiNoInternet:
                self?.notify(title: "Network Status", message: "⚠️ Wi‑Fi connected, but no internet", sound: "Funk")
            case .offline:
                self?.notify(title: "Network Status", message: "❌ Offline", sound: "Funk")
            }
        }
        watcher.start()
    }

    private func notify(title: String, message: String, sound: String? = nil) {
        var script = "display notification \"\(message)\" with title \"\(title)\""
        if let sound { script += " sound name \"\(sound)\"" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
}

let app = Pulse()
RunLoop.main.run()
