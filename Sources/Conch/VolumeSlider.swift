import AppKit
import SwiftUI

// MARK: - Native Slider

final class TrackingSlider: NSSlider {
    var editingChanged: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        prefersCompactControlSizeMetrics = false
    }

    required init?(coder: NSCoder) {
        fatalError("Programmatic slider only")
    }

    override func mouseDown(with event: NSEvent) {
        editingChanged(true)

        defer {
            editingChanged(false)
        }

        super.mouseDown(with: event)
    }
}

struct NativeVolumeSlider: NSViewRepresentable {
    @Binding var value: Double

    let label: String
    let muted: Bool
    let enabled: Bool

    var editingChanged: (Bool) -> Void = { _ in }

    final class Coordinator: NSObject {
        var parent: NativeVolumeSlider

        init(_ parent: NativeVolumeSlider) {
            self.parent = parent
        }

        @objc
        func changed(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider(frame: .zero)

        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.controlSize = .regular

        slider.target = context.coordinator
        slider.action = #selector(
            Coordinator.changed(_:)
        )

        slider.setContentHuggingPriority(
            .defaultLow,
            for: .horizontal
        )

        slider.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        return slider
    }

    func updateNSView(
        _ slider: TrackingSlider,
        context: Context
    ) {
        context.coordinator.parent = self

        slider.doubleValue = VolumeControl.clamped(value)
        slider.isEnabled = enabled
        slider.editingChanged = editingChanged

        slider.setAccessibilityLabel(label)

        slider.setAccessibilityValueDescription(
            muted
                ? "Muted; selected volume \(Int(value * 100)) percent"
                : "\(Int(value * 100)) percent"
        )
    }
}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    var level: Double
    var volume: Double
    var muted: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var displayedLevel: Double {
        guard !muted else {
            return 0
        }

        let clampedLevel = min(max(level, 0), 1)
        let clampedVolume = min(max(volume, 0), 1)

        return clampedLevel * clampedVolume
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.clear)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.25), .white.opacity(0.75)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * displayedLevel
                    )
            }
        }
        .frame(height: 6)
        .animation(
            reduceMotion
                ? nil
                : .linear(duration: 0.05),
            value: displayedLevel
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Volume Control

struct VolumeSlider: View {
    @Binding var value: Double

    var level: Double = 0
    var label: String

    var muted = false
    var enabled = true

    var editingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(
            alignment: .bottom,
            spacing: 5
        ) {
            stepButton(
                "speaker.fill",
                direction: -1,
                action: "Lower"
            )

            ZStack {

                // Completely stock macOS slider.
                NativeVolumeSlider(
                    value: $value,
                    label: label,
                    muted: muted,
                    enabled: enabled,
                    editingChanged: editingChanged
                )

                AudioLevelMeter(
                    level: level,
                    volume: value,
                    muted: muted
                )
                .frame(
                    maxWidth: .infinity,
                    minHeight: 22
                )
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)

            stepButton(
                "speaker.wave.3.fill",
                direction: 1,
                action: "Raise"
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(
        _ symbol: String,
        direction: Double,
        action: String
    ) -> some View {
        Button {
            value = VolumeControl.stepped(
                value,
                direction: direction
            )
        } label: {
            Image(systemName: symbol)
                .font(
                    .system(
                        size: 16,
                        weight: .medium
                    )
                )
                .foregroundStyle(.secondary)
                .frame(
                    height: 22
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            "\(action) \(label)"
        )
        .help(
            "\(action) volume"
        )
    }
}
