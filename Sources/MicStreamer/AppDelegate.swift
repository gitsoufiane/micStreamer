import AppKit
import AVFoundation
import CoreAudio

@available(macOS 14.2, *)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let captureBundleIDKey = "captureBundleID"
    private let captureNameKey = "captureName"
    private let microphoneEnabledKey = "microphoneMixEnabled"
    private let microphoneInputKey = "microphoneInputDeviceName"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let microphoneMixer = MicrophoneMixer()
    private var systemTapStreamer: SystemAudioTapStreamer?
    private var isRouting = false
    private var isMicrophoneMixing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [microphoneEnabledKey: true])
        let image = NSImage(
            systemSymbolName: "mic.and.signal.meter",
            accessibilityDescription: "MicStreamer"
        )
        statusItem.button?.image = image
        statusItem.button?.image?.isTemplate = true
        recoverStaleTapAggregate()
        refreshMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopStreaming()
    }

    @objc private func toggleRouting() {
        if isRouting {
            stopRouting()
        } else {
            startRouting()
        }
    }

    @objc private func toggleMicrophoneMix() {
        let enabled = !UserDefaults.standard.bool(forKey: microphoneEnabledKey)
        UserDefaults.standard.set(enabled, forKey: microphoneEnabledKey)

        if enabled && isRouting {
            startMicrophoneMixingWithPermission()
        } else {
            stopMicrophoneMixing()
            refreshMenu()
        }
    }

    @objc private func selectCaptureAll() {
        UserDefaults.standard.removeObject(forKey: captureBundleIDKey)
        UserDefaults.standard.removeObject(forKey: captureNameKey)
        restartIfRouting()
    }

    @objc private func selectCaptureProcess(_ sender: NSMenuItem) {
        guard let process = sender.representedObject as? AudioProcess else { return }
        UserDefaults.standard.set(process.bundleID, forKey: captureBundleIDKey)
        UserDefaults.standard.set(process.name, forKey: captureNameKey)
        restartIfRouting()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        UserDefaults.standard.set(name, forKey: microphoneInputKey)

        if isMicrophoneMixing {
            startMicrophoneMixingWithPermission()
        } else {
            refreshMenu()
        }
    }

    @objc private func refreshDevices() {
        refreshMenu()
    }

    @objc private func runSelfTest() {
        Task { @MainActor in
            do {
                let message = try await BlackHoleSelfTest().run()
                showMessage(message)
            } catch {
                show(error)
            }
        }
    }

    @objc private func openAudioMIDISetup() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func startRouting() {
        do {
            let blackHole = try AudioSystem.blackHoleOutputDevice()
            let streamer = SystemAudioTapStreamer()
            try streamer.start(outputDeviceID: blackHole.id, source: selectedCaptureSource())
            systemTapStreamer = streamer
            isRouting = true

            if UserDefaults.standard.bool(forKey: microphoneEnabledKey) {
                startMicrophoneMixingWithPermission()
            }
            refreshMenu()
        } catch {
            stopStreaming()
            show(error)
        }
    }

    private func stopRouting() {
        stopStreaming()
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()
        syncRoutingState()
        addRouteItems(to: menu)
        addCaptureItems(to: menu)
        addMicrophoneItems(to: menu)
        addUtilityItems(to: menu)

        statusItem.button?.toolTip = isRouting ? "MicStreamer routing is on" : "MicStreamer routing is off"
        statusItem.menu = menu
    }

    private func syncRoutingState() {
        isRouting = systemTapStreamer?.isRunning == true
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

@available(macOS 14.2, *)
private extension AppDelegate {
    func addRouteItems(to menu: NSMenu) {
        let toggle = NSMenuItem(
            title: isRouting ? "Stop Routing" : "Start Routing",
            action: #selector(toggleRouting),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: "Capture: \(selectedCaptureSource().title)", action: nil, keyEquivalent: ""))
    }

    func addCaptureItems(to menu: NSMenu) {
        let captureMenu = NSMenu()
        let all = NSMenuItem(title: "All Apps Except Calls", action: #selector(selectCaptureAll), keyEquivalent: "")
        all.target = self
        all.state = UserDefaults.standard.string(forKey: captureBundleIDKey) == nil ? .on : .off
        captureMenu.addItem(all)
        captureMenu.addItem(.separator())

        let selectedBundleID = UserDefaults.standard.string(forKey: captureBundleIDKey)
        for process in uniqueAudioProcesses() {
            let item = NSMenuItem(title: process.name, action: #selector(selectCaptureProcess(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = process
            item.state = process.bundleID == selectedBundleID ? .on : .off
            captureMenu.addItem(item)
        }

        let captureItem = NSMenuItem(title: "Capture Source", action: nil, keyEquivalent: "")
        menu.setSubmenu(captureMenu, for: captureItem)
        menu.addItem(captureItem)
    }

    func addMicrophoneItems(to menu: NSMenu) {
        let microphone = NSMenuItem(
            title: "Include Microphone",
            action: #selector(toggleMicrophoneMix),
            keyEquivalent: ""
        )
        microphone.target = self
        microphone.state = UserDefaults.standard.bool(forKey: microphoneEnabledKey) ? .on : .off
        menu.addItem(microphone)

        let microphoneMenu = NSMenu()
        let selectedName = selectedMicrophoneName()
        for device in ((try? AudioSystem.inputDevices()) ?? []).filter({ !AudioSystem.isBlackHole($0) }) {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.name
            item.state = device.name == selectedName ? .on : .off
            microphoneMenu.addItem(item)
        }

        let microphoneItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        menu.setSubmenu(microphoneMenu, for: microphoneItem)
        menu.addItem(microphoneItem)
    }

    func addUtilityItems(to menu: NSMenu) {
        menu.addItem(.separator())

        let setup = NSMenuItem(
            title: "Open Audio MIDI Setup",
            action: #selector(openAudioMIDISetup),
            keyEquivalent: ""
        )
        setup.target = self
        menu.addItem(setup)

        let selfTest = NSMenuItem(title: "Run BlackHole Self-Test", action: #selector(runSelfTest), keyEquivalent: "")
        selfTest.target = self
        menu.addItem(selfTest)

        let refresh = NSMenuItem(
            title: "Refresh Devices",
            action: #selector(refreshDevices),
            keyEquivalent: ""
        )
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    func selectedCaptureSource() -> CaptureSource {
        if let bundleID = UserDefaults.standard.string(forKey: captureBundleIDKey) {
            let name = UserDefaults.standard.string(forKey: captureNameKey) ?? bundleID
            return .process(bundleID: bundleID, name: name)
        }
        return .allExceptCalls
    }

    func uniqueAudioProcesses() -> [AudioProcess] {
        let ownBundleID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return ((try? AudioSystem.audioProcesses()) ?? []).filter { process in
            guard process.bundleID != ownBundleID,
                  !SystemAudioTapStreamer.callBundleIDs.contains(process.bundleID),
                  !seen.contains(process.bundleID) else {
                return false
            }
            seen.insert(process.bundleID)
            return true
        }
    }

    func restartIfRouting() {
        guard isRouting else {
            refreshMenu()
            return
        }
        stopStreaming()
        startRouting()
    }

    func stopStreaming() {
        stopMicrophoneMixing()
        systemTapStreamer?.stop()
        systemTapStreamer = nil
        try? AudioSystem.destroySystemTapAggregateIfExists()
        isRouting = false
    }

    func recoverStaleTapAggregate() {
        try? AudioSystem.destroySystemTapAggregateIfExists()
    }
}

@available(macOS 14.2, *)
private extension AppDelegate {
    func startMicrophoneMixingWithPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMicrophoneMixingIfStillEnabled()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                Task { @MainActor in
                    guard let self else { return }
                    if allowed {
                        self.startMicrophoneMixingIfStillEnabled()
                    } else {
                        self.disableMicrophoneMixing(message: "Microphone access was denied.")
                    }
                }
            }
        case .denied, .restricted:
            disableMicrophoneMixing(
                message: "Allow microphone access in System Settings to include your microphone."
            )
        @unknown default:
            disableMicrophoneMixing(message: "Microphone access is not available.")
        }
    }

    func startMicrophoneMixingIfStillEnabled() {
        guard isRouting && UserDefaults.standard.bool(forKey: microphoneEnabledKey) else { return }
        startMicrophoneMixing()
    }

    func startMicrophoneMixing() {
        do {
            let microphone = try selectedMicrophoneDevice()
            let blackHole = try AudioSystem.blackHoleOutputDevice()
            try microphoneMixer.start(inputDeviceID: microphone.id, outputDeviceID: blackHole.id)
            isMicrophoneMixing = true
            refreshMenu()
        } catch {
            stopMicrophoneMixing()
            UserDefaults.standard.set(false, forKey: microphoneEnabledKey)
            refreshMenu()
            show(error)
        }
    }

    func stopMicrophoneMixing() {
        microphoneMixer.stop()
        isMicrophoneMixing = false
    }

    func disableMicrophoneMixing(message: String) {
        stopMicrophoneMixing()
        UserDefaults.standard.set(false, forKey: microphoneEnabledKey)
        refreshMenu()
        show(MicrophoneMixerError(message: message))
    }

    func selectedMicrophoneDevice() throws -> AudioDevice {
        let inputs = try AudioSystem.inputDevices()
        if let savedName = UserDefaults.standard.string(forKey: microphoneInputKey),
           let saved = inputs.first(where: { $0.name == savedName }),
           !AudioSystem.isBlackHole(saved) {
            return saved
        }

        let defaultID = try? AudioSystem.defaultInputDeviceID()
        if let defaultID,
           let defaultInput = inputs.first(where: { $0.id == defaultID }),
           !AudioSystem.isBlackHole(defaultInput) {
            UserDefaults.standard.set(defaultInput.name, forKey: microphoneInputKey)
            return defaultInput
        }

        if let realInput = inputs.first(where: { !AudioSystem.isBlackHole($0) }) {
            UserDefaults.standard.set(realInput.name, forKey: microphoneInputKey)
            return realInput
        }

        throw AudioSystemError.missingDevice("No non-BlackHole microphone input was found.")
    }

    func selectedMicrophoneName() -> String? {
        if let savedName = UserDefaults.standard.string(forKey: microphoneInputKey) {
            return savedName
        }
        return try? selectedMicrophoneDevice().name
    }
}
