import SwiftUI
import Carbon

@main
struct ClipManagerApp: App {
    @StateObject private var watcher = ClipboardWatcher()
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            //header
            VStack(alignment: .leading, spacing: 0) {
                Text("copycat")
                    .font(.headline)
                
                if watcher.isMonitoring {
                    Text("● Monitoring On")
                        .font(.headline)
                        .foregroundColor(.green)
                } else {
                    Text("○ Monitoring Off")
                        .font(.headline)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            Button(watcher.isMonitoring ? "Disable Monitoring" : "Enable Monitoring") {
                watcher.isMonitoring.toggle()
            }
            
            Button("Clear History") {
                watcher.history.removeAll()
            }
            .disabled(watcher.history.isEmpty)
            
            Divider()
            
            if watcher.history.isEmpty {
                Text("No items copied yet")
                    .italic()
                    .foregroundColor(.gray)
            } else {
                ForEach(watcher.history, id: \.self) { item in
                    Button(action: {
                        copyToClipboard(item)
                    }) {
                        Text(item.prefix(40) + (item.count > 40 ? "..." : ""))
                    }
                }
            }
            
            Divider()
            
            //footer
            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.square")
            }
            
        } label: {
            let imageName = watcher.isMonitoring ? "cat_white_small" : "cat_asleep"
            let word = watcher.isMonitoring ? " Monitoring" : " Asleep"
            Text(word)
            Image(imageName)
        }
        
        //Settings window
        Settings {
            SettingsView(appState: appState, clipboardWatcher: watcher)
                .preferredColorScheme(appState.appearance.colorScheme)
        }
    }
    
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Open Menu with Hotkey
class AppDelegate: NSObject, NSApplicationDelegate {
    var eventMonitor: Any?
    var statusBarButton: NSStatusBarButton?
    var hotKeyRef: EventHotKeyRef?
    var eventHandler: EventHandlerRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        //Find the status bar button after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.findStatusBarButton()
        }
        
        //Register the initial hotkey
        registerHotkey(ShortcutManager.shared.currentShortcut)
        
        //listen for shortcut changes
        ShortcutManager.shared.onShortcutChanged = { [weak self] newShortcut in
            self?.unregisterHotkey()
            self?.registerHotkey(newShortcut)
            print("Hotkey updated to: \(newShortcut.displayString)")
        }
    }
    
    func registerHotkey(_ shortcut: KeyboardShortcut) {
        unregisterHotkey()
        
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            //convert NSEvent modifiers to Carbon format for comparison
            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var carbonModifiers: UInt32 = 0
            
            if eventModifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
            if eventModifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
            if eventModifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
            if eventModifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
            
            //check if keyCode and modifiers match
            if carbonModifiers == shortcut.modifiers && UInt32(event.keyCode) == shortcut.keyCode {
                print("Hotkey pressed: \(shortcut.displayString)")
                self?.openMenuBar()
            }
        }
        
        print("Hotkey registered: \(shortcut.displayString)")
    }
    
    func unregisterHotkey() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    func findStatusBarButton() {
        for window in NSApp.windows {
            if let button = self.searchForButton(in: window.contentView) {
                self.statusBarButton = button
                print("Found menu button!")
                return
            }
        }
        print("Menu button not found")
    }
    
    func searchForButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view = view else { return nil }
        
        if let button = view as? NSStatusBarButton {
            return button
        }
        
        for subview in view.subviews {
            if let button = searchForButton(in: subview) {
                return button
            }
        }
        
        return nil
    }
    
    func openMenuBar() {
        print("Opening menu bar")
        
        if statusBarButton == nil {
            findStatusBarButton()
        }
        
        if let button = statusBarButton {
            DispatchQueue.main.async {
                button.performClick(nil)
                print("Menu opened")
            }
        } else {
            print("Didn't find menu button")
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotkey()
    }
}
