import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .environmentObject(appState)

            HotkeySettingsView()
                .tabItem {
                    Label("Shortcut", systemImage: "keyboard")
                }
                .environmentObject(appState)

            NotificationSettingsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .environmentObject(appState)
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Watch folder:")
                    Spacer()
                    Text(appState.watchedFolder.path)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .foregroundStyle(.secondary)
                    Button("Change…") {
                        selectFolder()
                    }
                }

                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                        appState.save()
                    }

                Toggle("Batch mode", isOn: $appState.batchMode)
                    .onChange(of: appState.batchMode) { _ in
                        appState.save()
                    }
                Text("When enabled, the app stays armed after each download so you can redirect multiple files in a row. Press the hotkey again to disarm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Auto-disarm after:")
                    Spacer()
                    Picker("", selection: $appState.autoDisarmSeconds) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .onChange(of: appState.autoDisarmSeconds) { _ in
                        appState.save()
                    }
                }

                HStack {
                    Text("Recent destinations to remember:")
                    Spacer()
                    Picker("", selection: $appState.maxRecentDestinations) {
                        Text("3").tag(3)
                        Text("5").tag(5)
                        Text("10").tag(10)
                        Text("15").tag(15)
                    }
                    .labelsHidden()
                    .frame(width: 80)
                    .onChange(of: appState.maxRecentDestinations) { _ in
                        appState.save()
                    }
                }
            }

            if !appState.recentDestinations.isEmpty {
                Section("Recent Destinations") {
                    ForEach(appState.recentDestinations, id: \.self) { url in
                        Text(url.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Button("Clear Recent Destinations") {
                        appState.recentDestinations.removeAll()
                        appState.save()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose folder to watch"

        if panel.runModal() == .OK, let url = panel.url {
            appState.watchedFolder = url
            appState.save()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update login item: \(error)")
            }
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRecording = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Global shortcut to arm/disarm:")
                        .font(.headline)

                    HStack {
                        Text("Current shortcut:")
                        Spacer()
                        Text(appState.hotkeyDisplayString)
                            .font(.system(.title2, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accentColor.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                            )
                    }

                    HStack {
                        Spacer()
                        Button(isRecording ? "Press your shortcut…" : "Record New Shortcut") {
                            isRecording.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isRecording ? .orange : .accentColor)

                        if isRecording {
                            Button("Cancel") {
                                isRecording = false
                            }
                        }
                        Spacer()
                    }
                }
            }

            Section {
                Text("Press the button above, then press your desired key combination. The shortcut must include at least one modifier key (⌘, ⌥, ⌃, or ⇧).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .background(
            HotkeyRecorderView(isRecording: $isRecording) { keyCode, modifiers in
                appState.hotkeyKeyCode = keyCode
                appState.hotkeyModifiers = modifiers
                appState.save()
                isRecording = false

                // Re-register the hotkey
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.registerHotkey()
                }
            }
        )
    }
}

// MARK: - Notification Settings

struct NotificationSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Picker("After moving a file:", selection: $appState.notificationStyle) {
                    ForEach(AppState.NotificationStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: appState.notificationStyle) { _ in
                    appState.save()
                }
            }

            Section {
                Text("Notifications show the file name and destination folder after a successful move.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Hotkey Recorder (NSView bridge)

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecorded: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyCapture {
        let view = HotkeyCapture()
        view.onRecorded = onRecorded
        return view
    }

    func updateNSView(_ nsView: HotkeyCapture, context: Context) {
        nsView.isRecordingActive = isRecording
        nsView.onRecorded = onRecorded
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

class HotkeyCapture: NSView {
    var isRecordingActive = false
    var onRecorded: ((UInt32, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecordingActive else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.isEmpty else { return }

        let modifierRaw = UInt32(modifiers.rawValue)
        let keyCode = UInt32(event.keyCode)

        onRecorded?(keyCode, modifierRaw)
    }
}
