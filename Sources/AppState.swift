import Foundation
import Combine
import AppKit

class AppState: ObservableObject {
    @Published var isArmed: Bool = false
    @Published var watchedFolder: URL
    @Published var hotkeyKeyCode: UInt32
    @Published var hotkeyModifiers: UInt32
    @Published var launchAtLogin: Bool
    @Published var autoDisarmSeconds: Int
    @Published var maxRecentDestinations: Int
    @Published var notificationStyle: NotificationStyle
    @Published var recentDestinations: [URL]
    @Published var batchMode: Bool

    private var disarmTimer: Timer?

    enum NotificationStyle: String, CaseIterable, Codable {
        case banner = "Banner"
        case silent = "Silent"
        case sound = "Sound & Banner"
    }

    init() {
        let defaults = UserDefaults.standard

        let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        if let bookmarkData = defaults.data(forKey: "watchedFolder") {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale) {
                self.watchedFolder = url
            } else {
                self.watchedFolder = downloadsURL
            }
        } else {
            self.watchedFolder = downloadsURL
        }

        self.hotkeyKeyCode = UInt32(defaults.integer(forKey: "hotkeyKeyCode") == 0 ? 2 : defaults.integer(forKey: "hotkeyKeyCode")) // 'd' key
        self.hotkeyModifiers = UInt32(defaults.integer(forKey: "hotkeyModifiers") == 0 ? 0x100108 : defaults.integer(forKey: "hotkeyModifiers")) // Cmd+Shift
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.autoDisarmSeconds = defaults.integer(forKey: "autoDisarmSeconds") == 0 ? 30 : defaults.integer(forKey: "autoDisarmSeconds")
        self.maxRecentDestinations = defaults.integer(forKey: "maxRecentDestinations") == 0 ? 5 : defaults.integer(forKey: "maxRecentDestinations")

        self.batchMode = defaults.bool(forKey: "batchMode")

        if let styleRaw = defaults.string(forKey: "notificationStyle"),
           let style = NotificationStyle(rawValue: styleRaw) {
            self.notificationStyle = style
        } else {
            self.notificationStyle = .banner
        }

        if let data = defaults.data(forKey: "recentDestinations"),
           let urls = try? JSONDecoder().decode([String].self, from: data) {
            self.recentDestinations = urls.compactMap { URL(fileURLWithPath: $0) }
        } else {
            self.recentDestinations = []
        }
    }

    func save() {
        let defaults = UserDefaults.standard
        if let bookmarkData = try? watchedFolder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmarkData, forKey: "watchedFolder")
        }
        defaults.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode")
        defaults.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(autoDisarmSeconds, forKey: "autoDisarmSeconds")
        defaults.set(maxRecentDestinations, forKey: "maxRecentDestinations")
        defaults.set(batchMode, forKey: "batchMode")
        defaults.set(notificationStyle.rawValue, forKey: "notificationStyle")

        let paths = recentDestinations.map { $0.path }
        if let data = try? JSONEncoder().encode(paths) {
            defaults.set(data, forKey: "recentDestinations")
        }
    }

    func arm() {
        isArmed = true
        startDisarmTimer()
    }

    func disarm() {
        isArmed = false
        disarmTimer?.invalidate()
        disarmTimer = nil
    }

    func toggleArmed() {
        if isArmed {
            disarm()
        } else {
            arm()
        }
    }

    func addRecentDestination(_ url: URL) {
        recentDestinations.removeAll { $0 == url }
        recentDestinations.insert(url, at: 0)
        if recentDestinations.count > maxRecentDestinations {
            recentDestinations = Array(recentDestinations.prefix(maxRecentDestinations))
        }
        save()
    }

    private func startDisarmTimer() {
        disarmTimer?.invalidate()
        disarmTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(autoDisarmSeconds), repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.disarm()
            }
        }
    }

    var hotkeyDisplayString: String {
        var parts: [String] = []
        let mods = hotkeyModifiers
        if mods & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { parts.append("⌃") }
        if mods & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { parts.append("⌥") }
        if mods & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { parts.append("⇧") }
        if mods & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { parts.append("⌘") }

        let keyName = keyCodeToString(hotkeyKeyCode)
        parts.append(keyName)
        return parts.joined()
    }
}

import Carbon

func keyCodeToString(_ keyCode: UInt32) -> String {
    let mapping: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    return mapping[keyCode] ?? "Key\(keyCode)"
}
