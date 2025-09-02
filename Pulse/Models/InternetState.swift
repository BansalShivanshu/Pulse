//
//  InternetState.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-08.
//

enum InternetState: String, CaseIterable {
    case offline                // No route / transport
    case wifiNoInternet         // WiFi up but internet is unusable (captive/DNS/HTTP blocked)
    case online                 // Internet OK
}
