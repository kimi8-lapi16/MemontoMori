import Foundation
import AppKit
import SwiftUI
import Combine

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
    private var cancellables: Set<AnyCancellable> = []

    init(store: MemoStore) {
        self.store = store
        self.currentID = Self.resolveInitialID(store: store)
        installEventMonitor()
        observeRotationEnabled()
        observeTimingSettings()
        scheduleIdleTimer()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func observeRotationEnabled() {
        store.$rotationEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.scheduleIdleTimer()
                } else {
                    self.mode = .editing
                    self.stopRotationTimer()
                    self.idleTimer?.invalidate()
                    self.idleTimer = nil
                }
            }
            .store(in: &cancellables)
    }

    /// 設定パネルで間隔を変えても、すでに動いているタイマーは古い秒数のままなので張り直す。
    private func observeTimingSettings() {
        store.$idleTimeout
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .editing else { return }
                self.scheduleIdleTimer()
            }
            .store(in: &cancellables)

        store.$rotationInterval
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.mode == .rotating else { return }
                self.scheduleRotationTimer()
            }
            .store(in: &cancellables)

        // フォルダ移動やファイルの増減で対象が入れ替わったとき、待機タイマーが
        // 張られていないまま編集モードで固まらないようにする。
        store.$entries
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.ensureIdleTimerArmed()
            }
            .store(in: &cancellables)
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
        // 画像エントリは常にプレビュー固定。操作で編集モードに戻さず idle タイマーもリセットしない。
        // ただしタイマーが張られていないとローテーションへ移れなくなるため、張り直しはせず確保だけする。
        if let id = currentID, MemoEntry.isImage(id: id) {
            ensureIdleTimerArmed()
            return
        }
        if mode == .rotating {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    func reconcile() {
        let ids = store.entries.map(\.id)
        let currentValid = currentID.map { ids.contains($0) } ?? false
        if !currentValid {
            if let last = store.lastDisplayedID, ids.contains(last) {
                currentID = last
            } else {
                currentID = store.enabledEntries.first?.id ?? store.entries.first?.id
            }
            store.lastDisplayedID = currentID
        }
        if store.enabledEntries.isEmpty {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    /// - Parameter userInitiated: 矢印ボタンなど利用者の操作による送りかどうか。
    ///   自動送りの直後に割り込まれないよう、次の自動送りまでの間隔を測り直す。
    func advance(by step: Int = 1, userInitiated: Bool = false) {
        let enabled = store.enabledEntries
        guard !enabled.isEmpty else { return }
        store.flushPending()
        let currentIdx = enabled.firstIndex(where: { $0.id == currentID }) ?? -1
        let nextIdx = ((currentIdx + step) % enabled.count + enabled.count) % enabled.count
        currentID = enabled[nextIdx].id
        store.lastDisplayedID = currentID

        if userInitiated, mode == .rotating {
            scheduleRotationTimer()
        }
        ensureIdleTimerArmed()
    }

    func switchTo(id: String) {
        guard store.entries.contains(where: { $0.id == id }) else { return }
        store.flushPending()
        currentID = id
        store.lastDisplayedID = id
        ensureIdleTimerArmed()
    }

    func enterEditingMode() {
        if mode != .editing {
            mode = .editing
            stopRotationTimer()
        }
        scheduleIdleTimer()
    }

    /// すでに待機中なら何もしない。止まったままにならないよう、必要なときだけ張り直す。
    private func ensureIdleTimerArmed() {
        guard mode == .editing else { return }
        guard idleTimer == nil else { return }
        scheduleIdleTimer()
    }

    private func scheduleIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard store.rotationEnabled else { return }
        guard !store.enabledEntries.isEmpty else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: max(store.idleTimeout, 5),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // 発火済みタイマーは再利用されないので、張られていない状態として扱えるようにする。
                self.idleTimer = nil
                self.startRotation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func startRotation() {
        guard store.rotationEnabled else { return }
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
