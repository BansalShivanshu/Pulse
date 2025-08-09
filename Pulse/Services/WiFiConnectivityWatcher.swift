//
//  WiFiConnectivityWatcher.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Foundation
import Network

final class WiFiConnectivityWatcher {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "wifi.monitor.queue")
    private let service = ConnectivityService()

    var onChange: ((InternetState) -> Void)?

    // debouncing + in-flight guard
    private var debounceWork: DispatchWorkItem?
    private var isChecking = false
    private let debounceDelay: TimeInterval = 1  // 1 second

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            // cancel any scheduled check, then schedule a fresh one
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                // avoid overlapping probe bursts if events keep coming
                guard !self.isChecking else { return }
                self.isChecking = true

                self.service.checkInternet(on: path) { [weak self] state in
                    guard let self else { return }
                    self.isChecking = false
                    self.onChange?(state)
                }
            }
            self.debounceWork = work
            self.queue.asyncAfter(deadline: .now() + self.debounceDelay, execute: work)
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
