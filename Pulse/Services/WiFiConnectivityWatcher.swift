//
//  WiFiConnectivityWatcher.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Network

final class WiFiConnectivityWatcher {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "wifi.monitor.queue")
    private let service = ConnectivityService()

    var onChange: ((InternetState) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.service.checkInternet(on: path) { state in
                self.onChange?(state)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
