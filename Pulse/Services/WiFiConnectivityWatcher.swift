//
//  WiFiConnectivityWatcher.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Foundation
import Network

// MARK: - Configuration

private struct ConnectivityConfiguration {
    static let debounceDelay: TimeInterval = 0.8  // 800ms
    static let heartbeatBase: TimeInterval = 30     // seconds
    static let heartbeatJitter: TimeInterval = 5   // ±5s
    static let heartbeatMinInterval: TimeInterval = 20 // safety floor
}

final class WiFiConnectivityWatcher {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "wifi.monitor.queue")
    private let service = ConnectivityService()

    var onChange: ((InternetState) -> Void)?

    // Debounce + in‑flight guard
    private var debounceWork: DispatchWorkItem?
    private var isChecking = false

    // Heartbeat + jitter
    private var heartbeatTimer: DispatchSourceTimer?

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
            self.queue.asyncAfter(deadline: .now() + ConnectivityConfiguration.debounceDelay, execute: work)
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
        let jitter = Double.random(in: -ConnectivityConfiguration.heartbeatJitter...ConnectivityConfiguration.heartbeatJitter)
        return max(ConnectivityConfiguration.heartbeatMinInterval, ConnectivityConfiguration.heartbeatBase + jitter)
    }
}
