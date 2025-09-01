//
//  Notifications.swift
//  Pulse
//
//  Defines the Notifier protocol and implementations for delivering
//  user-facing notifications from a background agent or app.
//
//  Created by Shivanshu Bansal on 2025-08-09
//

import Foundation

// MARK: - Protocol

/// Abstract interface for sending a notification.
/// Allows swapping the delivery mechanism without changing the main app logic.
public protocol Notifier {
    func notify(title: String, body: String, sound: String?)
}

// MARK: - AppleScript / osascript notifier

/// Sends notifications using `osascript` to execute an AppleScript
/// `display notification` command. Works in LaunchAgents or CLI tools
/// without requiring user permission dialogs.
public final class OsaScriptNotifier: Notifier {
    public init() {}

    public func notify(title: String, body: String, sound: String? = nil) {
        let escTitle = Self.escapeForAppleScript(title)
        let escBody  = Self.escapeForAppleScript(body)

        var script = "display notification \"\(escBody)\" with title \"\(escTitle)\""
        if let s = sound, !s.isEmpty {
            let escSound = Self.escapeForAppleScript(s)
            script += " sound name \"\(escSound)\""
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        do {
            try p.run()
        } catch {
            fputs("Notification failed: \(error)\n", stderr)
        }
    }

    /// Escapes characters so they are safe to include inside AppleScript string literals.
    private static func escapeForAppleScript(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "\n", with: "\\n")
        return out
    }
}

// MARK: - No-op notifier

/// A Notifier that does nothing.
/// Useful for tests or situations where notifications are disabled.
public final class NoOpNotifier: Notifier {
    public init() {}
    public func notify(title: String, body: String, sound: String?) { /* intentionally empty */ }
}
