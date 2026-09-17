import AppKit
import Combine
import CoreAudio

@MainActor final class AppRow: ObservableObject, Identifiable {
    let id: AppSessionID
    let app: NSRunningApplication
    let name: String
    let bundleID: String?
    @Published var state: VolumeState
    @Published var active = false
    @Published var level: Double = 0
    @Published var error: String?
    var clients: [AudioClient] = []
    var route: AudioRoute?
    var lastActivity = Date.distantPast
    var envelope = MeterEnvelope()
    var lastTicks: UInt64 = 0
    var stalledChecks = 0
    init(_ client: AudioClient, state: VolumeState) {
        id = client.session
        app = client.owner
        name =
            app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent
            ?? "Audio App"
        bundleID = app.bundleIdentifier
        self.state = state
    }
}

@MainActor final class MixerModel: ObservableObject {
    @Published var rows: [AppRow] = []
    @Published var error: String?
    @Published var outputName = "System output"
    @Published var showInactive: Bool {
        didSet {
            defaults.set(showInactive, forKey: "showInactive")
            objectWillChange.send()
        }
    }
    @Published var meters: Bool {
        didSet {
            defaults.set(meters, forKey: "meters")
            updateMetering()
        }
    }
    var panelVisible = false {
        didSet {
            updateMetering()
            if panelVisible { sortRows() }
        }
    }
    var editing = false
    private let defaults: UserDefaults
    private var observations: [HALObservation] = []
    private var processObservations: [AudioObjectID: [HALObservation]] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var refreshPending = false
    private var suspended = false
    private var output: AudioObjectID = 0
    private var outputDirty = true
    private var outputObservations: [HALObservation] = []
    private var timer: Timer?
    private var watchdog: Timer?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInactive = defaults.object(forKey: "showInactive") as? Bool ?? true
        meters = defaults.object(forKey: "meters") as? Bool ?? true
        defaults.removeObject(forKey: "mixerEnabled")
    }
    func start() {
        for selector in [
            kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDevices,
        ] {
            do {
                observations.append(
                    try HALObservation(HAL.system, selector) { [weak self] in
                        Task { @MainActor in self?.scheduleRefresh() }
                    })
            } catch { self.error = error.localizedDescription }
        }
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            workspaceTokens.append(
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in Task { @MainActor in self?.scheduleRefresh() } })
        }
        workspaceTokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.suspended = false
                    self?.scheduleRefresh()
                    self?.updateMetering()
                }
            })
        workspaceTokens.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.suspended = true
                    self?.releaseRoutes()
                    self?.updateMetering()
                }
            })
        refresh()
    }
    func stop() {
        releaseRoutes()
        observations.removeAll()
        outputObservations.removeAll()
        processObservations.removeAll()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        timer?.invalidate()
        watchdog?.invalidate()
    }
    func retry(_ row: AppRow) {
        row.error = nil
        reconcileRoute(row)
        updateMetering()
    }
    func setVolume(_ value: Double, row: AppRow) {
        row.state.setVolume(value)
        apply(row)
    }
    func toggleMute(_ row: AppRow) {
        row.state.isMuted.toggle()
        apply(row)
    }
    private func apply(_ row: AppRow) {
        row.route?.setState(row.state)
        if row.state.isMuted || row.state.volume == 0 {
            row.level = 0
            row.envelope = MeterEnvelope()
        }
        if row.route == nil {
            row.error = nil
            reconcileRoute(row)
        }
        updateMetering()
    }
    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }
    private func releaseRoutes() {
        for row in rows {
            row.route = nil
            row.level = 0
        }
        updateWatchdog()
        updateMetering()
    }
    private func refresh() {
        guard !suspended else { return }
        do {
            let newOutput = try HAL.value(
                HAL.system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
            if newOutput != output || outputDirty {
                releaseRoutes()
                output = newOutput
                outputDirty = false
                for row in rows { row.error = nil }
                observeOutput()
            }
            outputName = (try? HAL.string(output, kAudioObjectPropertyName)) ?? "No output device"
            let objects = try HAL.objects(HAL.system, kAudioHardwarePropertyProcessObjectList)
            for id in Set(processObservations.keys).subtracting(objects) {
                processObservations.removeValue(forKey: id)
            }
            for id in objects where processObservations[id] == nil {
                var listeners: [HALObservation] = []
                for selector in [
                    kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyDevices,
                ] {
                    if let listener = try? HALObservation(
                        id, selector,
                        scope: selector == kAudioProcessPropertyDevices
                            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                        changed: { [weak self] in Task { @MainActor in self?.scheduleRefresh() } })
                    {
                        listeners.append(listener)
                    }
                }
                processObservations[id] = listeners
            }
            let apps = NSWorkspace.shared.runningApplications
            let clients = objects.compactMap { ProcessResolver.resolve($0, apps: apps) }
            let grouped = Dictionary(grouping: clients, by: \.session)
            // Launch identity includes date, preventing PID reuse from retaining mute.
            let alive = Set(
                apps.filter { !$0.isTerminated }.map {
                    AppSessionID(
                        pid: $0.processIdentifier, launchDate: $0.launchDate ?? .distantPast)
                })
            rows.removeAll { !alive.contains($0.id) }
            for (session, group) in grouped
            where group.contains(where: \.active) && !rows.contains(where: { $0.id == session }) {
                rows.append(AppRow(group[0], state: VolumeState()))
            }
            for row in rows {
                row.clients = grouped[row.id] ?? []
                let wasActive = row.active
                row.active = row.clients.contains(where: \.active)
                if row.active && !wasActive { row.lastActivity = Date() }
                reconcileRoute(row)
            }
            if !panelVisible && !editing { sortRows() }
            error = nil
        } catch {
            self.error = error.localizedDescription
            releaseRoutes()
        }
        updateWatchdog()
        updateMetering()
    }
    private func observeOutput() {
        outputObservations.removeAll()
        guard output != 0 else { return }
        let changed: () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.outputDirty = true
                self.releaseRoutes()
                self.scheduleRefresh()
            }
        }
        for selector in [
            kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyNominalSampleRate,
            kAudioDevicePropertyStreams,
        ] {
            if let observation = try? HALObservation(
                output, selector,
                scope: selector == kAudioDevicePropertyStreams
                    ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
                changed: changed)
            {
                outputObservations.append(observation)
            }
        }
        for stream
            in (try? HAL.objects(
                output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)) ?? []
        {
            if let observation = try? HALObservation(
                stream, kAudioStreamPropertyVirtualFormat, changed: changed)
            {
                outputObservations.append(observation)
            }
        }
    }
    private func reconcileRoute(_ row: AppRow) {
        guard row.active, output != 0 else {
            row.route = nil
            row.level = 0
            return
        }
        let processes = Set(row.clients.map(\.object))
        if let route = row.route, route.processes == processes, route.output == output { return }
        row.route = nil
        guard row.error == nil else { return }
        // One row must never silently control only part of an application's output.
        let destinations = row.clients.filter(\.active).reduce(into: Set<AudioObjectID>()) {
            $0.formUnion($1.devices)
        }
        guard destinations == [output] else {
            row.error =
                "This app uses a different or multiple outputs. Direct playback is unchanged."
            return
        }
        do {
            row.route = try AudioRoute(
                processes: processes, output: output, state: row.state,
                metering: panelVisible && meters
            ) { [weak self, weak row] in
                Task { @MainActor in
                    guard let self, let row else { return }
                    row.route = nil
                    row.error = nil
                    self.scheduleRefresh()
                }
            }
            row.lastTicks = 0
            row.stalledChecks = 0
        } catch { row.error = error.localizedDescription }
        updateWatchdog()
    }
    private func sortRows() {
        guard !editing else { return }
        rows.sort {
            if $0.active != $1.active { return $0.active }
            if $0.lastActivity != $1.lastActivity { return $0.lastActivity > $1.lastActivity }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    private func updateWatchdog() {
        let needed = rows.contains { $0.route != nil }
        if needed && watchdog == nil {
            watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    for row in self.rows {
                        guard let route = row.route else { continue }
                        let ticks = route.ticks
                        row.stalledChecks = ticks == row.lastTicks ? row.stalledChecks + 1 : 0
                        row.lastTicks = ticks
                        if route.failure || row.stalledChecks >= 3 {
                            row.route = nil
                            row.error =
                                "Audio routing stopped. Direct playback has been restored. Try again."
                        }
                    }
                    self.updateWatchdog()
                    self.updateMetering()
                }
            }
            watchdog?.tolerance = 0.2
        } else if !needed {
            watchdog?.invalidate()
            watchdog = nil
        }
    }
    private func updateMetering() {
        let shouldMeter = panelVisible && meters && !suspended && rows.contains { $0.route != nil }
        for row in rows {
            row.route?.setMetering(shouldMeter)
            if !shouldMeter {
                row.level = 0
                row.envelope = MeterEnvelope()
            }
        }
        if !shouldMeter {
            timer?.invalidate()
            timer = nil
        }
        if shouldMeter && timer == nil {
            timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                // This timer is installed on the main run loop in common modes.
                // Update synchronously so a nested slider tracking loop cannot defer it.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for row in self.rows {
                        let peak = row.route?.peak() ?? 0
                        if row.state.isMuted || row.state.volume == 0 {
                            row.envelope = MeterEnvelope()
                        } else {
                            row.envelope.update(peak: peak)
                        }
                        row.level = row.envelope.level
                    }
                }
            }
            timer?.tolerance = 0.01
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }
}
