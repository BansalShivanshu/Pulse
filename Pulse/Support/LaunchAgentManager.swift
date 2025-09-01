//
//  LaunchAgentManager.swift
//  Pulse
//
//  Created by Shivanshu Bansal on 2025-08-09.
//

import Foundation

public enum LaunchAgentManager {
    // Customize these as you like
    static let label = "com.shiv.pulse"
    static let agentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    static var plistURL: URL { agentsDir.appendingPathComponent("\(label).plist") }

    /// Absolute path to the currently running binary (resolves symlinks)
    static var currentBinaryPath: String {
        let arg0 = CommandLine.arguments.first ?? ""
        return (arg0 as NSString).resolvingSymlinksInPath
    }

    /// Installs (or replaces) the LaunchAgent and starts it immediately.
    public static func install() throws {
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        let plist = makePlist(programPath: currentBinaryPath)
        try plist.write(to: plistURL, atomically: true, encoding: .utf8)

        // If an old one is running, stop it first (ignore errors)
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])

        // Load and start
        _ = run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        _ = run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    /// Stops and removes the LaunchAgent if present.
    public static func uninstall() throws {
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    /// Generate a silent, login-starting, keepalive agent.
    private static func makePlist(programPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
         "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(label)</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(programPath)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>LimitLoadToSessionType</key>
          <string>Aqua</string>
          <key>StandardOutPath</key>
          <string>/dev/null</string>
          <key>StandardErrorPath</key>
          <string>/dev/null</string>
        </dict>
        </plist>
        """
    }

    @discardableResult
    private static func run(_ cmd: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cmd)
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

