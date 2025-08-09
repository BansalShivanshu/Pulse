//
//  ConnectivityService.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Foundation
import Network

/**
    Connectivity Service, probes Google, Cloudflare, Microsoft (HTTP) +
    TCP (Cloudflare, Google, Microsoft) IANA
 */
final class ConnectivityService {
    // --- HTTP probes (vendor diversity + different semantics)
    private let httpProbes: [HTTPProbe] = [
        // Google: tiny empty 204
        .init(url: URL(string: "https://www.google.com/generate_204")!,
              method: "HEAD", timeout: 3, expectation: .status(204...204)),

        // Cloudflare: small diagnostic text body
        .init(url: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!,
              method: "GET", timeout: 3, expectation: .bodyContains("h=")),

        // Microsoft NCSI / ConnectTest (HTTP, no TLS)
        .init(url: URL(string: "http://www.msftconnecttest.com/connecttest.txt")!,
              method: "GET", timeout: 3, expectation: .exactBody("Microsoft Connect Test")),
        .init(url: URL(string: "http://www.msftncsi.com/ncsi.txt")!,
              method: "GET", timeout: 3, expectation: .exactBody("Microsoft NCSI")),

        // IANA example.com (HTTP, no TLS dependency)
        .init(url: URL(string: "http://example.com/")!,
              method: "HEAD", timeout: 3, expectation: .status(200...299)),
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

        // HTTP Probes
        for p in httpProbes {
            group.enter()
            var req = URLRequest(url: p.url)
            req.httpMethod = p.method
            req.timeoutInterval = p.timeout

            session.dataTask(with: req) { data, resp, err in
                defer { group.leave() }
                guard err == nil, let http = resp as? HTTPURLResponse else { return }
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                let matched: Bool = {
                    switch p.expectation {
                    case .status(let r): return r.contains(http.statusCode)
                    case .exactBody(let s): return body.trimmingCharacters(in: .whitespacesAndNewlines) == s
                    case .bodyContains(let s): return body.contains(s)
                    }
                }()

                lock.lock()
                if matched { httpOK = true }
                else { sawHTTPResponseButUnexpected = true } // often captive portal / walled garden
                lock.unlock()
            }.resume()
        }

        // TCP probes
        for target in tcpTargets {
            group.enter()
            tcpConnect(host: target.host, port: target.port, timeout: 2.5) { ok in
                lock.lock(); if ok { tcpConnected = true }; lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            // Prioritize real web usability first
            if httpOK {
                completion(.online)
                return
            }

            // If we got HTTP responses but none matched expectations (common on captive portals),
            // prefer reporting "Wi‑Fi but no internet" right away.
            if sawHTTPResponseButUnexpected {
                if let path, path.status == .satisfied, path.usesInterfaceType(.wifi) {
                    completion(.wifiNoInternet)
                } else {
                    completion(.offline)
                }
                return
            }

            if tcpConnected {
                completion(.wifiNoInternet)
                return
            }

            if let path, path.status == .satisfied, path.usesInterfaceType(.wifi) {
                completion(.wifiNoInternet)
            } else {
                completion(.offline)
            }
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
