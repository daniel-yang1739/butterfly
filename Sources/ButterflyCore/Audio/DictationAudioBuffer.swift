import Foundation

/// Keeps each utterance anchored to its original audio until a pause or duration limit.
/// Snapshots are consumed in order; captured audio is never trimmed before acknowledgement.
package struct DictationAudioBuffer: Sendable {
    package struct Snapshot: Sendable {
        package let samples: [Float]
        package let speechEndSample: Int
        package let startSample: Int
        package let endSample: Int
        package let isFinal: Bool
    }

    private let trailingPaddingSamples: Int
    private let minimumVoiceSamples: Int
    private var voicedSamples = 0
    private var continuesPreviousUtterance = false
    private var lastVoiceEnd = 0
    private var acknowledgedSpeechEnd = 0
    private let maximumSamples: Int
    private let pauseSamples: Int
    private let minimumSamples: Int
    private let updateSamples: Int
    private var capturedSamples = 0
    private var activeStart = 0
    private var active: [Float] = []
    private var trailingSilence = 0
    private var completed: [Snapshot] = []
    private var acknowledgedEnd = 0

    package init(sampleRate: Int = 16_000) {
        precondition(sampleRate >= 10)
        trailingPaddingSamples = max(1, sampleRate / 10)
        minimumVoiceSamples = max(1, Int(Double(sampleRate) * 0.12))
        maximumSamples = sampleRate * 20
        pauseSamples = Int(Double(sampleRate) * 0.6)
        minimumSamples = sampleRate
        updateSamples = Int(Double(sampleRate) * 2.5)
    }

    package mutating func append(_ samples: [Float], isVoiced: Bool) {
        var offset = 0
        while offset < samples.count {
            // Silence outside an utterance has no transcript and needs no inference.
            if active.isEmpty && !isVoiced {
                continuesPreviousUtterance = false
                capturedSamples += samples.count - offset
                return
            }
            if active.isEmpty { activeStart = capturedSamples }
            let untilPause = isVoiced ? maximumSamples : max(1, pauseSamples - trailingSilence)
            let count = min(samples.count - offset, maximumSamples - active.count, untilPause)
            active.append(contentsOf: samples[offset..<(offset + count)])
            capturedSamples += count
            offset += count
            if isVoiced {
                voicedSamples += count
                lastVoiceEnd = active.count
            }
            trailingSilence = isVoiced ? 0 : trailingSilence + count
            if active.count == maximumSamples || trailingSilence >= pauseSamples {
                seal(continues: active.count == maximumSamples && trailingSilence == 0)
            }
        }
    }

    package mutating func finish() {
        seal()
    }

    package mutating func nextSnapshot() -> Snapshot? {
        // A pause may seal a snapshot while its last voiced samples are in flight.
        // Acknowledging that inference must not cause a second decode of silence.
        while let first = completed.first, first.speechEndSample <= acknowledgedSpeechEnd {
            completed.removeFirst()
        }
        if let first = completed.first { return first }
        guard hasSpeech,
              activeStart + lastVoiceEnd > acknowledgedSpeechEnd,
              active.count >= minimumSamples,
              capturedSamples - max(acknowledgedEnd, activeStart) >=
                (acknowledgedEnd <= activeStart ? minimumSamples : updateSamples) else { return nil }
        return snapshot(isFinal: false)
    }

    package mutating func acknowledge(_ snapshot: Snapshot) {
        acknowledgedEnd = max(acknowledgedEnd, snapshot.endSample)
        acknowledgedSpeechEnd = max(acknowledgedSpeechEnd, snapshot.speechEndSample)
        if snapshot.isFinal,
           let first = completed.first,
           first.startSample == snapshot.startSample,
           first.endSample == snapshot.endSample {
            completed.removeFirst()
        }
    }

    private func snapshot(isFinal: Bool) -> Snapshot {
        let count = min(active.count, lastVoiceEnd + trailingPaddingSamples)
        return Snapshot(
            samples: Array(active.prefix(count)),
            speechEndSample: activeStart + lastVoiceEnd,
            startSample: activeStart, endSample: activeStart + count, isFinal: isFinal
        )
    }

    private var hasSpeech: Bool {
        voicedSamples >= minimumVoiceSamples || (continuesPreviousUtterance && voicedSamples > 0)
    }

    private mutating func seal(continues: Bool = false) {
        guard !active.isEmpty else { return }
        if hasSpeech {
            completed.append(snapshot(isFinal: true))
        }
        // A duration split is not a new speech onset. Preserve its short final syllable.
        continuesPreviousUtterance = continues
        active = []
        trailingSilence = 0
        voicedSamples = 0
        lastVoiceEnd = 0
    }
}
