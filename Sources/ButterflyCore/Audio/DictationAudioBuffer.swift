import Foundation

/// Keeps each utterance anchored to its original audio until a pause or duration limit.
/// Snapshots are consumed in order; captured audio is never trimmed before acknowledgement.
struct DictationAudioBuffer: Sendable {
    struct Snapshot: Sendable {
        let samples: [Float]
        let startSample: Int
        let endSample: Int
        let isFinal: Bool
    }

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

    init(sampleRate: Int = 16_000) {
        precondition(sampleRate >= 10)
        maximumSamples = sampleRate * 20
        pauseSamples = Int(Double(sampleRate) * 0.6)
        minimumSamples = sampleRate
        updateSamples = Int(Double(sampleRate) * 2.5)
    }

    mutating func append(_ samples: [Float], isVoiced: Bool) {
        var offset = 0
        while offset < samples.count {
            // Silence outside an utterance has no transcript and needs no inference.
            if active.isEmpty && !isVoiced {
                capturedSamples += samples.count - offset
                return
            }
            if active.isEmpty { activeStart = capturedSamples }
            let untilPause = isVoiced ? maximumSamples : max(1, pauseSamples - trailingSilence)
            let count = min(samples.count - offset, maximumSamples - active.count, untilPause)
            active.append(contentsOf: samples[offset..<(offset + count)])
            capturedSamples += count
            offset += count
            trailingSilence = isVoiced ? 0 : trailingSilence + count
            if active.count == maximumSamples || trailingSilence >= pauseSamples {
                seal()
            }
        }
    }

    mutating func finish() {
        seal()
    }

    func nextSnapshot() -> Snapshot? {
        if let first = completed.first { return first }
        guard active.count >= minimumSamples,
              capturedSamples - max(acknowledgedEnd, activeStart) >=
                (acknowledgedEnd <= activeStart ? minimumSamples : updateSamples) else { return nil }
        return Snapshot(samples: active, startSample: activeStart, endSample: capturedSamples, isFinal: false)
    }

    mutating func acknowledge(_ snapshot: Snapshot) {
        acknowledgedEnd = max(acknowledgedEnd, snapshot.endSample)
        // A partial snapshot may have become sealed during inference. It must still
        // receive a final pass, including any samples captured in the meantime.
        if snapshot.isFinal,
           let first = completed.first,
           first.startSample == snapshot.startSample,
           first.endSample == snapshot.endSample {
            completed.removeFirst()
        }
    }

    private mutating func seal() {
        guard !active.isEmpty else { return }
        completed.append(Snapshot(
            samples: active, startSample: activeStart, endSample: capturedSamples, isFinal: true
        ))
        active = []
        trailingSilence = 0
    }
}
