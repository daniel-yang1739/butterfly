import Foundation

/// Offline regressions using production audio segmentation, merging, and delta planning.
/// No microphone, model, clipboard, or keyboard events are used.
@main
struct TranscriptReplay {
    static var checks = 0

    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name)
        checks += 1
        print("PASS: \(name)")
    }

    static func main() {
        testRevisions()
        testAudioLifecycle()
        testSlowInference()
        print("\n\(checks) offline regression checks passed.")
    }

    static func testRevisions() {
        let transcript = TranscriptAccumulator()
        let injector = InputInjector()
        var predicted = ""
        var cursor = ""
        let revisions = [
            "We need to check the supported components",
            "We need to check the available components including databases and queues",
            "We should check the available database and queue services before starting integration tests.",
            "We should check the available database and queue services before starting integration tests today.",
            "Check the available services.",
            "Check the available services!",
            "",
            "Check the available services."
        ]
        for text in revisions {
            let merged = transcript.updateSegment(rawText: text, segmentStartSample: 0)
            check(merged == text, "An anchored revision replaces the complete active text")
            let action = injector.prepareStreamingDelta(newText: merged, previousText: &predicted)
            apply(action, to: &cursor)
            check(cursor == text && predicted == text, "Cursor matches the requested revision")
            check(injector.prepareStreamingDelta(newText: merged, previousText: &predicted) == .noChange,
                  "Repeated snapshots are idempotent")
        }
        let repeated = transcript.updateSegment(rawText: revisions.last!, segmentStartSample: 80_000)
        check(repeated == "Check the available services. Check the available services.",
              "An intentional repetition in a distinct audio segment is preserved")
        let revised = transcript.updateSegment(rawText: "Check the database.", segmentStartSample: 80_000)
        check(revised == "Check the available services. Check the database.",
              "Revising a later segment preserves committed text")
        check(transcript.updateSegment(rawText: "stale", segmentStartSample: 0) == revised,
              "A stale segment cannot replace current text")
    }

    static func testAudioLifecycle() {
        // Small sample rate makes exact audio ownership easy to inspect.
        var audio = DictationAudioBuffer(sampleRate: 10)
        audio.append(Array(repeating: 0, count: 100), isVoiced: false)
        check(audio.nextSnapshot() == nil, "Idle silence does not trigger inference")
        audio.append(Array(repeating: 1, count: 10), isVoiced: true)
        let partial = audio.nextSnapshot()!
        check(partial.startSample == 100 && partial.endSample == 110 && !partial.isFinal,
              "Initial speech retains its absolute start")
        audio.acknowledge(partial)
        check(audio.nextSnapshot() == nil, "Unchanged audio is not transcribed repeatedly")
        audio.append(Array(repeating: 2, count: 25), isVoiced: true)
        let growing = audio.nextSnapshot()!
        check(growing.startSample == 100 && growing.samples == partial.samples + Array(repeating: 2, count: 25),
              "A growing utterance keeps all earlier audio")
        audio.acknowledge(growing)
        audio.append(Array(repeating: 0, count: 6), isVoiced: false)
        let final = audio.nextSnapshot()!
        check(final.isFinal && final.startSample == 100 && final.endSample == 141,
              "A pause seals the same utterance")
        audio.acknowledge(final)
        audio.append([3, 3], isVoiced: true)
        check(audio.nextSnapshot() == nil, "Short speech waits for more audio")
        audio.finish()
        let shortFinal = audio.nextSnapshot()!
        check(shortFinal.startSample == 141 && shortFinal.samples == [3, 3] && shortFinal.isFinal,
              "Stop flushes speech shorter than the initial threshold")
        audio.acknowledge(shortFinal)
        check(audio.nextSnapshot() == nil, "Finalization drains all audio")
    }

    static func testSlowInference() {
        var audio = DictationAudioBuffer(sampleRate: 10)
        let samples = (0..<450).map { Float($0) }
        audio.append(Array(samples.prefix(10)), isVoiced: true)
        let inFlight = audio.nextSnapshot()!
        audio.append(Array(samples.dropFirst(10)), isVoiced: true)
        audio.acknowledge(inFlight)
        audio.finish()
        var restored: [Float] = []
        var previousEnd = 0
        var count = 0
        while let snapshot = audio.nextSnapshot() {
            check(snapshot.isFinal && snapshot.startSample == previousEnd,
                  "Queued segments own contiguous non-overlapping audio")
            check(snapshot.samples.count <= 200, "Inference input is bounded to twenty seconds")
            restored += snapshot.samples
            previousEnd = snapshot.endSample
            audio.acknowledge(snapshot)
            count += 1
        }
        check(count == 3 && restored == samples, "Slow inference neither drops nor duplicates captured samples")
    }

    static func apply(_ action: SlidingDeltaAction, to cursor: inout String) {
        switch action {
        case .append(let text): cursor += text
        case .replaceTail(let count, let replacement):
            precondition(count <= cursor.count)
            cursor.removeLast(count)
            cursor += replacement
        case .noChange: break
        }
    }
}
