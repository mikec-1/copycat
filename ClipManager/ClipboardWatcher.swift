import SwiftUI
import AppKit
import Combine

struct IgnoredApp: Identifiable, Codable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
}

class ClipboardWatcher: ObservableObject {
    
    //limits the number of items stored. Persisted via AppStorage.
    @AppStorage("historyLimit") private var historyLimit: Int = 20
    @AppStorage("ignorePasswordManagers") var ignorePasswordManagers: Bool = true
    @AppStorage("ignoreCustomApps") var ignoreCustomApps: Bool = true
    

    @Published var ignoredApps: [IgnoredApp] = [] {
        didSet {
            //autosaves to disk whenever this list changes
            if let encoded = try? JSONEncoder().encode(ignoredApps) {
                UserDefaults.standard.set(encoded, forKey: "customIgnoredApps")
            }
        }
    }
    
    @Published var isMonitoring: Bool = true {
        didSet {
            //stops app from adding copied items after unpaused
            if isMonitoring { lastChangeCount = pasteboard.changeCount }
        }
    }
    
    @Published var history: [String] = [] {
        didSet {
            //saves changes to UserDefaults when history array is modified
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
        //load saved history from disk on startup
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
        //poll the clipboard every 0.5 seconds to check for changes
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
        
        //only proceed if something new is copied
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            //privacy check
            //app currently in front
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               let bundleID = frontApp.bundleIdentifier {
                
                //checks password app list
                if ignorePasswordManagers {
                    if builtInRestrictedApps.contains(bundleID) {
                        print("Ignored copy from Password Manager (\(bundleID))")
                        return //stops and doesn't save
                    }
                }
                
                //checks custom apps
                if ignoreCustomApps {
                    //checks if current app ID is in the custom list
                    if ignoredApps.contains(where: { $0.bundleID == bundleID }) {
                        print("Custom Rule: Ignored copy from \(frontApp.localizedName ?? bundleID)")
                        return
                    }
                }
            }
            //privacy end
            
            //if checks passed save the text
            if let newString = pasteboard.string(forType: .string) {
                
                //removes duplicates
                if let index = history.firstIndex(of: newString) {
                    history.remove(at: index)
                }
                
                //adds to top
                history.insert(newString, at: 0)
                
                if history.count > historyLimit {
                    history.removeLast()
                }
            }
        }
    }
}
