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
    private let notifier: Notifier = OsaScriptNotifier()
    private var lastState: InternetState?

    init() {
        // Self-install flags (nice dev ergonomics)
        if CommandLine.arguments.contains("--install-agent") {
            do { try LaunchAgentManager.install(); print("✅ Installed & started LaunchAgent") }
            catch { fputs("❌ Install failed: \(error)\n", stderr); exit(1) }
            exit(0)
        }
        if CommandLine.arguments.contains("--uninstall-agent") {
            do { try LaunchAgentManager.uninstall(); print("🗑️  Uninstalled LaunchAgent") }
            catch { fputs("⚠️ Uninstall error: \(error)\n", stderr); exit(1) }
            exit(0)
        }
        
        watcher.onChange = { [weak self] state in
            guard state != self?.lastState else { return }   // only notify on change
            self?.lastState = state

            switch state {
            case .online:
                self?.notifier.notify(title: "Network Status", body: "✅ Internet is available", sound: "Glass")
            case .wifiNoInternet:
                self?.notifier.notify(title: "Network Status", body: "⚠️ WiFi connected, but no internet", sound: "Funk")
            case .offline:
                self?.notifier.notify(title: "Network Status", body: "❌ Offline", sound: "Funk")
            }
        }
        watcher.start()
    }
}

let app = Pulse()
RunLoop.main.run()
