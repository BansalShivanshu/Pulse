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

    // Debounce + in‑flight guard
    private var debounceWork: DispatchWorkItem?
    private var isChecking = false
    private let debounceDelay: TimeInterval = 0.8  // 800ms

    // Heartbeat + jitter
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatBase: TimeInterval = 30     // seconds
    private let heartbeatJitter: TimeInterval = 5   // ±10s
        private let heartbeatMinInterval: TimeInterval = 20 // safety floor

    func start() {
        // Start path monitoring
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            // Debounce bursts of events
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.runCheck(for: path)
            }
            self.debounceWork = work
            self.queue.asyncAfter(deadline: .now() + self.debounceDelay, execute: work)
        }
        monitor.start(queue: queue)

        // Start heartbeat with initial jittered delay
        scheduleNextHeartbeat()
    }

    func stop() {
        monitor.cancel()
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: - Internals

    private func runCheck(for path: NWPath?) {
        // Avoid overlapping probe bursts
        guard !isChecking else { return }
        isChecking = true

        service.checkInternet(on: path) { [weak self] state in
            guard let self else { return }
            self.isChecking = false
            self.onChange?(state)
        }
    }

    private func scheduleNextHeartbeat() {
        // Cancel any existing timer
        heartbeatTimer?.cancel()
        heartbeatTimer = DispatchSource.makeTimerSource(queue: queue)

        let interval = jitteredInterval()
        heartbeatTimer?.schedule(deadline: .now() + interval, repeating: .never)

        heartbeatTimer?.setEventHandler { [weak self] in
            guard let self else { return }
            // currentPath is always a valid NWPath once the monitor has started
            let path = self.monitor.currentPath
            self.runCheck(for: path)
            // schedule next tick with fresh jitter
            self.scheduleNextHeartbeat()
        }

        heartbeatTimer?.resume()
    }

    private func jitteredInterval() -> TimeInterval {
        // base ± jitter, but never below a minimum safety floor
        let jitter = Double.random(in: -heartbeatJitter...heartbeatJitter)
        return max(heartbeatMinInterval, heartbeatBase + jitter)
    }
}
