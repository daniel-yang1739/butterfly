import Foundation

/// Owns recognition generations and waits for a terminal callback without audio hardware.
@MainActor
package final class SpeechRecognitionSession {
    package private(set) var requestID: UUID?
    package private(set) var transcript = ""
    private var committed = ""
    private var active = ""
    private var terminal = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    package init() {}

    package func reset() {
        invalidate()
        committed = ""
        active = ""
        transcript = ""
    }

    @discardableResult
    package func beginRequest() -> UUID {
        invalidate()
        committed = transcript
        active = ""
        terminal = false
        let id = UUID()
        requestID = id
        return id
    }

    @discardableResult
    package func receive(_ text: String, isFinal: Bool, requestID id: UUID) -> Bool {
        guard requestID == id, !terminal else { return false }
        // An empty final callback still completes the request and preserves its partial.
        if !text.isEmpty {
            active = text
            let separator = committed.isEmpty || active.isEmpty
                || committed.last.map({ "。 ，！？；.!?;".contains($0) }) == true ? "" : "，"
            transcript = committed + separator + active
        }
        if isFinal { complete(requestID: id) }
        return true
    }

    package func complete(requestID id: UUID) {
        guard requestID == id, !terminal else { return }
        terminal = true
        resumeWaiters()
    }

    package func invalidate() {
        requestID = nil
        terminal = true
        resumeWaiters()
    }

    /// The timeout only bounds a missing callback; it is not a fixed grace period.
    package func waitForFinal(timeoutNanoseconds: UInt64 = 2_000_000_000) async {
        guard requestID != nil, !terminal, !Task.isCancelled else { return }
        let waiterID = UUID()
        let timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            self?.resumeWaiter(waiterID)
        }
        defer { timeout.cancel() }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if terminal || Task.isCancelled { continuation.resume() }
                else { waiters[waiterID] = continuation }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resumeWaiter(waiterID) }
        }
    }

    private func resumeWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }

    private func resumeWaiters() {
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
