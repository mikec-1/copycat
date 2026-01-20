import SwiftUI
import AppKit
import Combine

struct IgnoredApp: Identifiable, Codable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

class ClipboardWatcher: ObservableObject {
    
    // Limits the number of items stored. Persisted via AppStorage.
    @AppStorage("historyLimit") private var historyLimit: Int = 20
    @AppStorage("ignorePasswordManagers") var ignorePasswordManagers: Bool = true
    @AppStorage("ignoreCustomApps") var ignoreCustomApps: Bool = true
    

    @Published var ignoredApps: [IgnoredApp] = [] {
        didSet {
            // Auto-save to disk whenever this list changes
            if let encoded = try? JSONEncoder().encode(ignoredApps) {
                UserDefaults.standard.set(encoded, forKey: "customIgnoredApps")
            }
        }
    }
    
    @Published var isMonitoring: Bool = true {
        didSet {
            // When resuming, sync the change count immediately.
            // This prevents the app from "catching up" on items copied while paused.
            if isMonitoring { lastChangeCount = pasteboard.changeCount }
        }
    }
    
    @Published var history: [String] = [] {
        didSet {
            // Auto-save changes to UserDefaults whenever the history array is modified
            UserDefaults.standard.set(history, forKey: "ClipboardHistory")
        }
    }
    
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    
    private let builtInRestrictedApps: Set<String> = [
        "com.agilebits.onepassword7",   // 1Password 7
        "com.1password.1password",      // 1Password 8
        "com.lastpass.LastPass",        // LastPass
        "com.apple.keychainaccess",     // macOS Keychain
        "com.apple.Passwords",          // Apple Passwords
        "com.dashlane.Dashlane",        // Dashlane
        "com.dashlane.DashlaneAgent",   // Dashlane Agent
        "com.bitwarden.desktop",        // Bitwarden
        "org.keepassxc.keepassxc"       // KeePassXC
    ]
    
    init() {
        // Load saved history from disk on startup
        if let savedHistory = UserDefaults.standard.stringArray(forKey: "ClipboardHistory") {
            self.history = savedHistory
        }
        
        if let savedAppsData = UserDefaults.standard.data(forKey: "customIgnoredApps"),
           let decodedApps = try? JSONDecoder().decode([IgnoredApp].self, from: savedAppsData) {
            self.ignoredApps = decodedApps
        }

        self.lastChangeCount = pasteboard.changeCount
        startWatching()
    }
    
    func startWatching() {
        // Poll the clipboard every 0.5 seconds to check for changes
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func updateHistorySize(_ size: Int) {
            historyLimit = size
            if history.count > historyLimit {
                history = Array(history.prefix(historyLimit))
            }
        }
    
    
    private func checkClipboard() {
        guard isMonitoring else { return }
        
        // Only proceed if the clipboard counter changed (something new was copied)
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            
            // --- SECURITY CHECK START ---
            
            // 1. Get the app currently in front (The one the user copied from)
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier {
                
                // 2. Check "Password Manager Protection"
                if ignorePasswordManagers {
                    if builtInRestrictedApps.contains(bundleID) {
                        print("Security: Ignored copy from Password Manager (\(bundleID))")
                        return // STOP HERE. Do not save.
                    }
                }
                
                // 3. Check "Custom Rules"
                if ignoreCustomApps {
                    // Check if the current app's ID is in our custom list
                    if ignoredApps.contains(where: { $0.bundleID == bundleID }) {
                        print("Custom Rule: Ignored copy from \(frontApp.localizedName ?? bundleID)")
                        return // STOP HERE. Do not save.
                    }
                }
            }
            // --- SECURITY CHECK END ---
            
            // If we passed the checks, save the text
            if let newString = pasteboard.string(forType: .string) {
                
                // Remove duplicate if it exists elsewhere in the list
                if let index = history.firstIndex(of: newString) {
                    history.remove(at: index)
                }
                
                // Add to top
                history.insert(newString, at: 0)
                
                // Trim to limit
                if history.count > historyLimit {
                    history.removeLast()
                }
            }
        }
    }
}
