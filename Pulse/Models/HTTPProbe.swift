//
//  HTTPProbe.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

import Foundation

struct HTTPProbe {
    enum Expectation {
        case status(ClosedRange<Int>)            // e.g. 204...204 or 200...299
        case exactBody(String)                   // exact match
        case bodyContains(String)                // substring match
    }
    let url: URL
    let method: String           // "HEAD" or "GET"
    let timeout: TimeInterval
    let expectation: Expectation
}
