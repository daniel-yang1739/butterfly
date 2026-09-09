import XCTest
@testable import ButterflyCore

final class DictationAudioBufferTests: XCTestCase {
    func testGrowingAudioKeepsItsAnchorAndPauseSealsIt() throws {
        var audio = DictationAudioBuffer(sampleRate: 10)
        audio.append(Array(repeating: 1, count: 10), isVoiced: true)
        let first = try XCTUnwrap(audio.nextSnapshot())
        audio.acknowledge(first)
        audio.append(Array(repeating: 2, count: 25), isVoiced: true)
        let second = try XCTUnwrap(audio.nextSnapshot())
        XCTAssertEqual(second.startSample, first.startSample)
        XCTAssertEqual(Array(second.samples.prefix(10)), first.samples)
        audio.acknowledge(second)
        audio.append(Array(repeating: 0, count: 6), isVoiced: false)
        let final = try XCTUnwrap(audio.nextSnapshot())
        XCTAssertTrue(final.isFinal)
        XCTAssertEqual(final.startSample, first.startSample)
        XCTAssertEqual(final.endSample, 41)
    }

    func testSlowInferenceDoesNotDiscardOrReplayAudio() throws {
        var audio = DictationAudioBuffer(sampleRate: 10)
        let samples = (0..<450).map { Float($0) }
        audio.append(Array(samples.prefix(10)), isVoiced: true)
        let pending = try XCTUnwrap(audio.nextSnapshot())
        audio.append(Array(samples.dropFirst(10)), isVoiced: true)
        audio.acknowledge(pending)
        audio.finish()
        var reconstructed: [Float] = []
        var end = 0
        while let snapshot = audio.nextSnapshot() {
            XCTAssertTrue(snapshot.isFinal)
            XCTAssertEqual(snapshot.startSample, end)
            XCTAssertLessThanOrEqual(snapshot.samples.count, 200)
            reconstructed += snapshot.samples
            end = snapshot.endSample
            audio.acknowledge(snapshot)
        }
        XCTAssertEqual(reconstructed, samples)
    }

    func testStopFlushesShortSpeechButIdleSilenceHasNoSnapshot() throws {
        var audio = DictationAudioBuffer(sampleRate: 10)
        audio.append(Array(repeating: 0, count: 100), isVoiced: false)
        XCTAssertNil(audio.nextSnapshot())
        audio.append([1, 2], isVoiced: true)
        XCTAssertNil(audio.nextSnapshot())
        audio.finish()
        let final = try XCTUnwrap(audio.nextSnapshot())
        XCTAssertEqual(final.startSample, 100)
        XCTAssertEqual(final.samples, [1, 2])
        audio.acknowledge(final)
        XCTAssertNil(audio.nextSnapshot())
    }

    func testSegmentRevisionsDoNotDuplicateWordingChanges() {
        let transcript = TranscriptAccumulator()
        _ = transcript.updateSegment(rawText: "We need to check supported components", segmentStartSample: 0)
        let revision = "We should check the available components before running the integration tests."
        XCTAssertEqual(transcript.updateSegment(rawText: revision, segmentStartSample: 0), revision)
        XCTAssertEqual(transcript.updateSegment(rawText: revision, segmentStartSample: 320_000), revision + " " + revision)
        XCTAssertEqual(transcript.updateSegment(rawText: "Check again.", segmentStartSample: 320_000), revision + " Check again.")
        XCTAssertEqual(transcript.updateSegment(rawText: "", segmentStartSample: 320_000), revision)
    }
}
