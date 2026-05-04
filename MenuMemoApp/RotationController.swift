import Foundation
import AppKit
import SwiftUI

@MainActor
final class RotationController: ObservableObject {
    enum Mode: Equatable {
        case editing
        case rotating
    }

    @Published private(set) var mode: Mode = .editing
    @Published private(set) var currentID: String?

    private let store: MemoStore
    private var idleTimer: Timer?
    private var rotationTimer: Timer?
    private var eventMonitor: Any?

    init(store: MemoStore) {
        self.store = store
        self.currentID = Self.resolveInitialID(store: store)
        installEventMonitor()
        scheduleIdleTimer()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private static func resolveInitialID(store: MemoStore) -> String? {
        if let last = store.lastDisplayedID,
           store.entries.contains(where: { $0.id == last }) {
            return last
        }
        return store.enabledEntries.first?.id ?? store.entries.first?.id
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.handleUserInteraction()
            }
            return event
        }
    }

    func handleUserInteraction() {
        if mode == .rotating {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    func reconcile() {
        let ids = store.entries.map(\.id)
        if let cur = currentID, !ids.contains(cur) {
            currentID = store.enabledEntries.first?.id ?? store.entries.first?.id
            store.lastDisplayedID = currentID
        }
        if currentID == nil {
            currentID = store.enabledEntries.first?.id ?? store.entries.first?.id
            store.lastDisplayedID = currentID
        }
        if store.enabledEntries.isEmpty {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    func advance(by step: Int = 1) {
        let enabled = store.enabledEntries
        guard !enabled.isEmpty else { return }
        store.flushPending()
        let currentIdx = enabled.firstIndex(where: { $0.id == currentID }) ?? -1
        let nextIdx = ((currentIdx + step) % enabled.count + enabled.count) % enabled.count
        currentID = enabled[nextIdx].id
        store.lastDisplayedID = currentID
    }

    func switchTo(id: String) {
        guard store.entries.contains(where: { $0.id == id }) else { return }
        store.flushPending()
        currentID = id
        store.lastDisplayedID = id
    }

    func enterEditingMode() {
        if mode != .editing {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard !store.enabledEntries.isEmpty else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: max(store.idleTimeout, 5),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startRotation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func startRotation() {
        let enabled = store.enabledEntries
        guard !enabled.isEmpty else { return }
        store.flushPending()
        mode = .rotating
        if let cur = currentID, !enabled.contains(where: { $0.id == cur }) {
            currentID = enabled[0].id
            store.lastDisplayedID = currentID
        } else if currentID == nil {
            currentID = enabled[0].id
            store.lastDisplayedID = currentID
        }
        scheduleRotationTimer()
    }

    private func scheduleRotationTimer() {
        rotationTimer?.invalidate()
        let timer = Timer.scheduledTimer(
            withTimeInterval: max(store.rotationInterval, 5),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.advance()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rotationTimer = timer
    }

    private func stopRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
    }
}
