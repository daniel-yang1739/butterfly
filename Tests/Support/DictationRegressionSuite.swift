import Foundation
import ButterflyCore

/// Shared behavioral checks for XCTest and CLI-only developer installations.
@MainActor
public enum DictationRegressionSuite {
    public struct Check: Sendable {
        public let name: String
        public let passed: Bool
    }

    public static func audio() -> [Check] {
        var checks: [Check] = []
        func check(_ name: String, _ passed: Bool) { checks.append(Check(name: name, passed: passed)) }
        var audio = DictationAudioBuffer(sampleRate: 100)
        audio.append(Array(repeating: 0, count: 500), isVoiced: false)
        audio.finish()
        check("Silence never schedules inference", audio.nextSnapshot() == nil)
        audio.append(Array(repeating: 1, count: 2), isVoiced: true)
        audio.append(Array(repeating: 0, count: 60), isVoiced: false)
        check("A brief click cannot create a speech segment", audio.nextSnapshot() == nil)

        audio = DictationAudioBuffer(sampleRate: 100)
        audio.append(Array(repeating: 1, count: 100), isVoiced: true)
        if let pending = audio.nextSnapshot() {
            audio.append(Array(repeating: 0, count: 60), isVoiced: false)
            audio.acknowledge(pending)
            check("A pause during inference cannot decode the same speech again", audio.nextSnapshot() == nil)
            audio.finish()
            check("Stopping after a pause cannot append a hallucinated continuation", audio.nextSnapshot() == nil)
        } else { check("Initial speech snapshot exists", false) }

        audio = DictationAudioBuffer(sampleRate: 100)
        audio.append(Array(repeating: 1, count: 100), isVoiced: true)
        if let pending = audio.nextSnapshot() {
            audio.append(Array(repeating: 2, count: 20), isVoiced: true)
            audio.append(Array(repeating: 0, count: 60), isVoiced: false)
            audio.acknowledge(pending)
            let final = audio.nextSnapshot()
            check("New speech captured during inference receives a final decode", final?.speechEndSample == 120)
            check("Final decode retains only 100ms of trailing silence", final?.samples.count == 130)
            if let final { audio.acknowledge(final) }
            check("Final decode is consumed exactly once", audio.nextSnapshot() == nil)
        }
        audio.append(Array(repeating: 3, count: 20), isVoiced: true)
        audio.finish()
        let short = audio.nextSnapshot()
        check("A short spoken reply survives stop and retains its sample anchor", short?.startSample == 180 && short?.samples.count == 20)

        audio = DictationAudioBuffer(sampleRate: 100)
        let samples = (0..<4_500).map(Float.init)
        audio.append(Array(samples.prefix(100)), isVoiced: true)
        let partial = audio.nextSnapshot()
        audio.append(Array(samples.dropFirst(100)), isVoiced: true)
        if let partial { audio.acknowledge(partial) }
        audio.finish()
        var recovered: [Float] = []
        while let snapshot = audio.nextSnapshot() {
            recovered += snapshot.samples
            audio.acknowledge(snapshot)
        }
        check("Slow inference preserves all speech across the duration limit", recovered == samples)
        audio = DictationAudioBuffer(sampleRate: 100)
        audio.append(Array(repeating: 1, count: 2_005), isVoiced: true)
        audio.finish()
        var sampleCount = 0
        while let snapshot = audio.nextSnapshot() {
            sampleCount += snapshot.samples.count
            audio.acknowledge(snapshot)
        }
        check("A short final syllable after the 20-second split is not mistaken for a click", sampleCount == 2_005)
        let transcript = TranscriptAccumulator()
        let spokenEnglish = "Thank you. And then waiting for the next step."
        check("Common hallucination phrases are preserved when actually transcribed",
              transcript.updateSegment(rawText: spokenEnglish, segmentStartSample: 0) == spokenEnglish)
        return checks
    }

    public static func recognition() async -> [Check] {
        var checks: [Check] = []
        func check(_ name: String, _ passed: Bool) { checks.append(Check(name: name, passed: passed)) }
        let session = SpeechRecognitionSession()
        let first = session.beginRequest()
        session.receive("Initial", isFinal: false, requestID: first)
        var completed = false
        let waiter = Task { @MainActor in
            await session.waitForFinal(timeoutNanoseconds: 2_000_000_000)
            completed = true
        }
        // Specifically regress the old 200ms grace period.
        try? await Task.sleep(nanoseconds: 300_000_000)
        check("Stopping waits beyond 200ms for the final recognition callback", !completed)
        session.receive("Initial sentence completed.", isFinal: true, requestID: first)
        await waiter.value
        check("The late final words are preserved", session.transcript == "Initial sentence completed.")
        check("Duplicate final callbacks are rejected", !session.receive("Duplicate", isFinal: true, requestID: first))

        let second = session.beginRequest()
        check("Recycled requests reject callbacks from the previous request", !session.receive("Stale", isFinal: false, requestID: first))
        session.receive("Next", isFinal: false, requestID: second)
        session.receive("", isFinal: true, requestID: second)
        await session.waitForFinal(timeoutNanoseconds: 1)
        check("An empty final completes without losing the partial", session.transcript == "Initial sentence completed.Next")

        session.reset()
        let third = session.beginRequest()
        session.receive("Keep partial", isFinal: false, requestID: third)
        await session.waitForFinal(timeoutNanoseconds: 1_000_000)
        check("A missing final callback times out without discarding text", session.transcript == "Keep partial")
        let cancelled = Task { @MainActor in await session.waitForFinal(timeoutNanoseconds: 60_000_000_000) }
        cancelled.cancel()
        await cancelled.value
        check("Cancellation releases the final-result waiter", session.transcript == "Keep partial")
        session.complete(requestID: third)
        await session.waitForFinal(timeoutNanoseconds: 60_000_000_000)
        check("A terminal error releases the final-result waiter", session.transcript == "Keep partial")
        session.reset()
        check("A new recording rejects the previous recording's final callback", !session.receive("Old", isFinal: true, requestID: third) && session.transcript.isEmpty)
        let fourth = session.beginRequest()
        let firstWaiter = Task { @MainActor in await session.waitForFinal(timeoutNanoseconds: 60_000_000_000) }
        let secondWaiter = Task { @MainActor in await session.waitForFinal(timeoutNanoseconds: 60_000_000_000) }
        await settle()
        session.complete(requestID: fourth)
        await firstWaiter.value
        await secondWaiter.value
        check("A terminal error resumes all pending waiters", true)
        return checks
    }

    public static func coordinator() async -> [Check] {
        var checks: [Check] = []
        func check(_ name: String, _ passed: Bool) { checks.append(Check(name: name, passed: passed)) }
        let output = RecordingOutput()
        let machine = ButterflyStateMachine(output: output)
        let source = ControlledSpeechSource()
        source.finalText = "Hello world."
        var transitions: [ButterflyState] = []
        machine.onStateChange = { transitions.append($0) }
        await machine.start(mode: .liveStreaming, source: source)
        source.publish("Hello")
        await settle()
        check("The production coordinator streams partial text", output.text == "Hello")
        let oldCallback = source.transcriptCallback
        source.holdStop = true
        output.holdDrain = true
        let stopping = Task { @MainActor in await machine.stop() }
        await settle()
        await machine.stop()
        let otherSource = ControlledSpeechSource()
        await machine.start(mode: .liveStreaming, source: otherSource)
        check("Duplicate stop and start during finalization are blocked", source.stopCount == 1 && otherSource.startCount == 0)
        source.releaseStop()
        await settle()
        check("Final text is reconciled while state remains processing until output drains", output.text == "Hello world." && machine.currentState == .processing(.liveStreaming))
        output.releaseDrain()
        await stopping.value
        check("The recording lifecycle follows the App's actual states", transitions == [.starting(.liveStreaming), .recording(.liveStreaming), .processing(.liveStreaming), .idle])
        check("No paste is used during live dictation", output.inserted.isEmpty)

        let next = ControlledSpeechSource()
        next.finalText = "Original text"
        var polishCount = 0
        await machine.start(mode: .smartPolish, source: next) { text in
            polishCount += 1
            return SmartPolishResult(text: "Edited: " + text, usedFallback: false)
        }
        oldCallback?("Stale previous recording")
        next.publish("Partial draft")
        await settle()
        check("Smart Polish buffers text and ignores old-session callbacks", machine.latestTranscript == "Partial draft" && output.text == "Hello world.")
        await machine.stop()
        check("Smart Polish uses final text and inserts exactly once", polishCount == 1 && output.inserted == ["Edited: Original text"])

        let empty = ControlledSpeechSource()
        await machine.start(mode: .smartPolish, source: empty) { text in
            polishCount += 1
            return SmartPolishResult(text: text, usedFallback: false)
        }
        await machine.stop()
        check("Empty recordings neither polish nor insert", polishCount == 1 && output.inserted.count == 1)

        let failed = ControlledSpeechSource()
        failed.failStart = true
        var errors = 0
        machine.onError = { _ in
            errors += 1
            check("Errors are reported after recording and output cleanup", machine.currentState == .idle)
        }
        await machine.start(mode: .liveStreaming, source: failed)
        check("Startup failure releases the source and returns to idle", errors == 1 && failed.stopCount == 1 && machine.currentState == .idle)

        let failingSource = ControlledSpeechSource()
        await machine.start(mode: .liveStreaming, source: failingSource)
        failingSource.errorCallback?(ButterflyError.inferenceFailed("Test failure"))
        await settle()
        check("Recognition errors finalize the active recording", errors == 2 && failingSource.stopCount == 1 && machine.currentState == .idle)

        let startingSource = ControlledSpeechSource()
        startingSource.holdStart = true
        let starting = Task { @MainActor in await machine.start(mode: .liveStreaming, source: startingSource) }
        await settle()
        await machine.start(mode: .liveStreaming, source: startingSource)
        check("Repeated start during permission or model loading is blocked", startingSource.startCount == 1 && machine.currentState == .starting(.liveStreaming))
        starting.cancel()
        startingSource.releaseStart()
        await starting.value
        check("Cancellation during startup stops the source without injecting", startingSource.stopCount == 1 && machine.currentState == .idle)

        let polishSource = ControlledSpeechSource()
        polishSource.finalText = "Waiting for polish"
        var polishing = false
        await machine.start(mode: .smartPolish, source: polishSource) { text in
            polishing = true
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            return SmartPolishResult(text: text, usedFallback: false)
        }
        let polishingTask = Task { @MainActor in await machine.stop() }
        await settle()
        check("Smart Polish remains processing while generation is pending", polishing && machine.currentState == .processing(.smartPolish))
        polishingTask.cancel()
        await polishingTask.value
        check("Cancelled polishing never pastes a result", output.inserted.count == 1 && machine.currentState == .idle)

        let pasteFailure = ControlledSpeechSource()
        pasteFailure.finalText = "Paste failure"
        output.insertSucceeds = false
        await machine.start(mode: .smartPolish, source: pasteFailure)
        await machine.stop()
        check("Failed insertion reports an error and permits a new recording", errors == 3 && machine.currentState == .idle)
        return checks
    }

    private static func settle() async {
        // Callback delivery hops to MainActor; let all queued deliveries run.
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class ControlledSpeechSource: DictationSpeechSource {
    var transcriptCallback: (@Sendable (String) -> Void)?
    var errorCallback: (@Sendable (Error) -> Void)?
    var finalText = ""
    var failStart = false
    var holdStart = false
    var holdStop = false
    var startCount = 0
    var stopCount = 0
    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var startContinuation: CheckedContinuation<Void, Never>?

    func start(onTranscript: @escaping @Sendable (String) -> Void,
               onAudioLevel: @escaping @Sendable (Float) -> Void,
               onError: @escaping @Sendable (Error) -> Void) async throws {
        startCount += 1
        transcriptCallback = onTranscript
        errorCallback = onError
        if holdStart { await withCheckedContinuation { startContinuation = $0 } }
        if failStart { throw ButterflyError.audioCaptureFailed("Test startup failure") }
    }
    func publish(_ text: String) { transcriptCallback?(text) }
    func releaseStart() {
        holdStart = false
        startContinuation?.resume()
        startContinuation = nil
    }
    func stop() async -> String {
        stopCount += 1
        if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
        return finalText
    }
    func releaseStop() {
        holdStop = false
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

@MainActor
private final class RecordingOutput: DictationTextOutput {
    var text = ""
    var inserted: [String] = []
    var insertSucceeds = true
    var holdDrain = false
    private var drainContinuation: CheckedContinuation<Void, Never>?
    func update(_ text: String, previousText: inout String) {
        self.text = text
        previousText = text
    }
    func drain() async {
        if holdDrain { await withCheckedContinuation { drainContinuation = $0 } }
    }
    func insert(_ text: String) async -> Bool {
        guard insertSucceeds else { return false }
        inserted.append(text)
        return true
    }
    func releaseDrain() {
        holdDrain = false
        drainContinuation?.resume()
        drainContinuation = nil
    }
}
