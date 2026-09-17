import AppKit
import Combine
import ServiceManagement
import SwiftUI

// MARK: - App

@main
struct ConchApp: App {
    @StateObject private var controller = ConchController()

    var body: some Scene {
        MenuBarExtra {
            MixerPanel(
                model: controller.model,
                output: controller.output
            )
            .onAppear {
                controller.model.panelVisible = true
            }
            .onDisappear {
                controller.model.panelVisible = false
                controller.model.editing = false
            }
        } label: {
            MenuBarVolumeIcon(
                volume: controller.output.volume,
                muted: controller.output.isMuted
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                model: controller.model
            )
        }
    }
}

// MARK: - Menu Bar Volume Icon
private struct MenuBarVolumeIcon: View {
    let volume: Double?
    let muted: Bool

    private var normalizedVolume: Double {
        guard !muted else { return 0 }
        return min(max(volume ?? 0, 0), 1)
    }

    var body: some View {
        Group {
            if muted {
                Image(systemName: "speaker.slash.fill")
            } else {
                Image(
                    systemName: "speaker.wave.3.fill",
                    variableValue: normalizedVolume
                )
            }
        }
        .accessibilityLabel(
            muted
                ? "Muted"
                : "Volume \(Int(normalizedVolume * 100)) percent"
        )
    }
}

// MARK: - App Controller

@MainActor
final class ConchController: ObservableObject {
    let model = MixerModel()
    let output = OutputVolumeModel()

    private var subscriptions = Set<AnyCancellable>()

    init() {
        // Forward changes from the child models so the MenuBarExtra
        // label updates when the volume or mute state changes.
        model.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        output.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &subscriptions)

        let isTestHost =
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        if !isTestHost {
            output.start()
            model.start()
        }
    }
}

// MARK: - Menu Button

// MARK: - Menu Button

private struct MenuButton: View {
    let title: String
    let contentInset: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(.primary.opacity(0.7))
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                // Text lines up with the main panel content,
                // while the hover background extends farther.
                .padding(.horizontal, contentInset)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .fill(
                isHovered
                    ? Color.primary.opacity(0.10)
                    : .clear
            )
        }
        .onHover {
            isHovered = $0
        }
    }
}

// MARK: - Mixer Panel
private let contentInset: CGFloat = 10

struct MixerPanel: View {
    @ObservedObject var model: MixerModel
    @ObservedObject var output: OutputVolumeModel

    @Environment(\.openSettings) private var openSettings

    // Small padding around the actual window.
    private let outerPadding: CGFloat = 4

    private var visibleRows: [AppRow] {
        model.rows.filter {
            model.showInactive || $0.active
        }
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {

            // MARK: Sound

            LazyVStack(
                alignment: .leading,
                spacing: 5
            ) {
                Color.clear
                    .frame(height: 4)

                Text("Sound")
                    .font(.headline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.8))

                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    VolumeSlider(
                        value: Binding(
                            get: {
                                output.volume ?? 0
                            },
                            set: output.setVolume
                        ),
                        label: "System volume",
                        muted: output.isMuted,
                        enabled: output.canAdjust
                    )

                    Text(output.name)
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineLimit(1)

                    if !output.canAdjust {
                        Text(
                            "Volume is controlled by this output device."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let error = output.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, contentInset)

            Divider().padding(.horizontal, contentInset)

            // MARK: Applications

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                if let error = model.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if visibleRows.isEmpty {
                    VStack(
                        alignment: .leading,
                        spacing: 4
                    ) {
                        Text("No Apps Playing Audio")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.85))

                        Text(
                            "Apps will appear here after they play sound."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)

                } else {
                    ScrollView {
                        LazyVStack(
                            alignment: .leading,
                            spacing: 12
                        ) {
                            ForEach(visibleRows) { row in
                                MixerRow(
                                    row: row,
                                    model: model
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(
                        height: min(
                            visibleRows.reduce(CGFloat(0)) {
                                $0 + ($1.error == nil ? 66 : 136)
                            },
                            350
                        )
                    )
                }
            }
            .padding(.horizontal, contentInset)

            // This divider also uses the wider panel width.
            Divider()

            // MARK: Footer

            VStack(
                alignment: .leading,
                spacing: 0
            ) {
                MenuButton(
                    title: "Conch Settings…",
                    contentInset: contentInset
                ) {
                    NSApp.activate(
                        ignoringOtherApps: true
                    )

                    openSettings()
                }

                MenuButton(
                    title: "Sound Settings…",
                    contentInset: contentInset
                ) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.Sound-Settings.extension"
                        )!
                    )
                }

                MenuButton(
                    title: "Quit Conch",
                    contentInset: contentInset
                ) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(outerPadding)
        .frame(width: 310)
        .fixedSize(
            horizontal: false,
            vertical: true
        )
    }
}

// MARK: - App Mixer Row

struct MixerRow: View {
    @ObservedObject var row: AppRow
    @ObservedObject var model: MixerModel

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            HStack(spacing: 8) {
                Button {
                    model.toggleMute(row)
                } label: {
                    Image(
                        nsImage:
                            row.app.icon
                            ?? NSImage(
                                systemSymbolName: "app",
                                accessibilityDescription: nil
                            )!
                    )
                    .resizable()
                    .frame(
                        width: 26,
                        height: 26
                    )
                    .opacity(
                        row.state.isMuted ? 0.45 : 1
                    )
                    .overlay(
                        alignment: .bottomTrailing
                    ) {
                        if row.state.isMuted {
                            Image(
                                systemName: "speaker.slash.fill"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .semibold
                                )
                            )
                            .padding(2)
                            .background(
                                .background,
                                in: Circle()
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(row.error != nil)
                .accessibilityLabel(
                    "\(row.state.isMuted ? "Unmute" : "Mute") \(row.name)"
                )
                .help(
                    row.state.isMuted
                        ? "Unmute \(row.name)"
                        : "Mute \(row.name)"
                )

                Text(row.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
            }

            VolumeSlider(
                value: Binding(
                    get: {
                        row.state.volume
                    },
                    set: {
                        model.setVolume(
                            $0,
                            row: row
                        )
                    }
                ),
                level: row.level,
                label: "\(row.name) volume",
                muted: row.state.isMuted,
                enabled: row.error == nil,
                editingChanged: {
                    model.editing = $0
                }
            )

            if let error = row.error {
                HStack(alignment: .top) {
                    Text(error)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    Button("Retry") {
                        model.retry(row)
                    }
                    .buttonStyle(.link)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: MixerModel

    @StateObject private var login = LoginSettings()

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: {
                            login.enabled
                        },
                        set: { enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }

                                login.enabled =
                                    SMAppService.mainApp.status == .enabled

                                login.error =
                                    SMAppService.mainApp.status
                                        == .requiresApproval
                                    ? "Allow Conch in System Settings → General → Login Items."
                                    : nil
                            } catch {
                                login.error =
                                    error.localizedDescription
                            }
                        }
                    )
                )

                if let error = login.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Show inactive audio apps until they quit",
                    isOn: $model.showInactive
                )

                Toggle(
                    "Show audio levels",
                    isOn: $model.meters
                )
            }

            Section("FaceTime") {
                Text(
                    "Conch can adjust captured app audio. macOS does not expose a supported way for Conch to disable FaceTime’s audio ducking."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Section {
                Button(
                    "System Audio Recording Permissions…"
                ) {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                        )!
                    )
                }

                Text(
                    "Audio is processed in memory, never saved or transmitted. Volumes and mute reset when an app quits."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(
            horizontal: false,
            vertical: true
        )
        .onAppear {
            NSApp.activate(
                ignoringOtherApps: true
            )

            login.enabled =
                SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - Login Settings

@MainActor
final class LoginSettings: ObservableObject {
    @Published
    var enabled =
        SMAppService.mainApp.status == .enabled

    @Published
    var error: String?
}
