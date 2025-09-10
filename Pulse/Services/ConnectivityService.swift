//
//  ConnectivityService.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Foundation
import Network

// MARK: - Configuration

private struct ProbeConfiguration {
    static let HTTP_TIMEOUT: TimeInterval = 3.0
    static let TCP_TIMEOUT: TimeInterval = 2.5
}

/**
    Connectivity Service, probes Google, Cloudflare, Microsoft (HTTP) +
    TCP (Cloudflare, Google, Microsoft) IANA
 */
final class ConnectivityService {
    // --- HTTP probes (vendor diversity + different semantics)
    private let httpProbes: [HTTPProbe] = [
        // Google: tiny empty 204
        .init(url: URL(string: "https://www.google.com/generate_204")!,
              method: "HEAD", timeout: ProbeConfiguration.HTTP_TIMEOUT, expectation: .status(204...204)),

        // Cloudflare: small diagnostic text body
        .init(url: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!,
              method: "GET", timeout: ProbeConfiguration.HTTP_TIMEOUT, expectation: .bodyContains("h=")),

        // Microsoft NCSI / ConnectTest (HTTP, no TLS)
        .init(url: URL(string: "http://www.msftconnecttest.com/connecttest.txt")!,
              method: "GET", timeout: ProbeConfiguration.HTTP_TIMEOUT, expectation: .exactBody("Microsoft Connect Test")),
        .init(url: URL(string: "http://www.msftncsi.com/ncsi.txt")!,
              method: "GET", timeout: ProbeConfiguration.HTTP_TIMEOUT, expectation: .exactBody("Microsoft NCSI")),

        // IANA example.com (HTTP, no TLS dependency)
        .init(url: URL(string: "http://example.com/")!,
              method: "HEAD", timeout: ProbeConfiguration.HTTP_TIMEOUT, expectation: .status(200...299)),
    ]

    // Raw TCP to avoid DNS/HTTP dependencies (Cloudflare + Google)
    private let tcpTargets: [(host: NWEndpoint.Host, port: NWEndpoint.Port)] = [
        ("1.1.1.1", 443),
        ("8.8.8.8", 443),

        // Microsoft edges via DNS (works in regions where Google may be blocked)
        ("www.microsoft.com", 443),
        ("www.bing.com", 443),
    ]

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    /// Run probes in parallel. If any HTTP probe meets expectation OR any TCP probe connects, we declare .online.
    /// If Wi‑Fi is the active path but all probes fail or look like captive/portal, we return .wifiNoInternet.
    func checkInternet(on path: NWPath?, completion: @escaping (InternetState) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()

        var httpOK = false
        var sawHTTPResponseButUnexpected = false
        var tcpConnected = false

        // Run HTTP probes
        runHTTPProbes(group: group, lock: lock) { isOK, sawUnexpected in
            lock.lock()
            if isOK { httpOK = true }
            if sawUnexpected { sawHTTPResponseButUnexpected = true }
            lock.unlock()
        }

        // Run TCP probes
        runTCPProbes(group: group, lock: lock) { connected in
            lock.lock()
            if connected { tcpConnected = true }
            lock.unlock()
        }

        // Evaluate results when all probes complete
        group.notify(queue: .main) {
            let state = self.determineInternetState(
                httpOK: httpOK,
                sawHTTPResponseButUnexpected: sawHTTPResponseButUnexpected,
                tcpConnected: tcpConnected,
                path: path
            )
            completion(state)
        }
    }

    // MARK: - Private Helper Methods

    private func runHTTPProbes(
        group: DispatchGroup,
        lock: NSLock,
        onResult: @escaping (Bool, Bool) -> Void
    ) {
        for probe in httpProbes {
            group.enter()
            executeHTTPProbe(probe: probe) { isOK, sawUnexpected in
                onResult(isOK, sawUnexpected)
                group.leave()
            }
        }
    }

    private func executeHTTPProbe(
        probe: HTTPProbe,
        completion: @escaping (Bool, Bool) -> Void
    ) {
        var req = URLRequest(url: probe.url)
        req.httpMethod = probe.method
        req.timeoutInterval = probe.timeout

        session.dataTask(with: req) { data, resp, err in
            guard err == nil, let http = resp as? HTTPURLResponse else { 
                completion(false, false)
                return 
            }
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

            let matched = self.evaluateHTTPExpectation(probe.expectation, response: http, body: body)
            completion(matched, !matched)
        }.resume()
    }

    private func evaluateHTTPExpectation(_ expectation: HTTPProbe.Expectation, response: HTTPURLResponse, body: String) -> Bool {
        switch expectation {
        case .status(let range): 
            return range.contains(response.statusCode)
        case .exactBody(let expected): 
            return body.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        case .bodyContains(let substring): 
            return body.contains(substring)
        }
    }

    private func runTCPProbes(
        group: DispatchGroup,
        lock: NSLock,
        onResult: @escaping (Bool) -> Void
    ) {
        for target in tcpTargets {
            group.enter()
            tcpConnect(host: target.host, port: target.port, timeout: ProbeConfiguration.TCP_TIMEOUT) { connected in
                onResult(connected)
                group.leave()
            }
        }
    }

    private func determineInternetState(
        httpOK: Bool,
        sawHTTPResponseButUnexpected: Bool,
        tcpConnected: Bool,
        path: NWPath?
    ) -> InternetState {
        // Prioritize real web usability first
        if httpOK {
            return .online
        }

        // If we got HTTP responses but none matched expectations (common on captive portals),
        // prefer reporting "Wi‑Fi but no internet" right away.
        if sawHTTPResponseButUnexpected {
            if let path, path.status == .satisfied, path.usesInterfaceType(.wifi) {
                return .wifiNoInternet
            } else {
                return .offline
            }
        }

        if tcpConnected {
            return .wifiNoInternet
        }

        if let path, path.status == .satisfied, path.usesInterfaceType(.wifi) {
            return .wifiNoInternet
        } else {
            return .offline
        }
    }

    private func tcpConnect(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        let deadline = DispatchTime.now() + timeout
        var finished = false

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if !finished { finished = true; conn.cancel(); completion(true) }
            case .failed, .cancelled:
                if !finished { finished = true; completion(false) }
            default: break
            }
        }
        conn.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
            if !finished { finished = true; conn.cancel(); completion(false) }
        }
    }
}
