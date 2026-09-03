import XCTest
@testable import ButterflyCore

final class InferenceEngineTests: XCTestCase {
    
    // TC-C1: Mock inference backend verification
    func testMockInferenceBackend() async throws {
        let expectedText = "Mock speech recognition test"
        let backend = MockInferenceBackend(mockResult: TranscriptionResult(
            rawText: expectedText,
            confidence: 0.99,
            latencySeconds: 0.05,
            detectedLanguage: "zh",
            usedHardware: .metalGPU
        ))
        
        try await backend.initialize(modelPath: "test.bin")
        XCTAssertTrue(backend.isInitialized)
        
        let audioSamples: [Float] = [0.1, 0.2, 0.3, 0.2, 0.1]
        let result = try await backend.transcribe(audioSamples: audioSamples)
        
        XCTAssertEqual(result.rawText, expectedText)
        XCTAssertEqual(result.usedHardware, .metalGPU)
        XCTAssertEqual(backend.transcribedSamplesHistory.count, 1)
    }
    
    // TC-C2: Audio resampling accuracy test
    func testAudioResamplingAccuracy() {
        // Resample from 48,000 Hz to 16,000 Hz (3:1 downsampling)
        let sample48k: [Float] = [0.0, 0.5, 1.0, 0.5, 0.0, -0.5, -1.0, -0.5, 0.0]
        let resampled = AudioCaptureManager.resample(inputSamples: sample48k, fromSampleRate: 48000, toSampleRate: 16000)
        
        XCTAssertEqual(resampled.count, 3)
    }

    func testCoreMLEncoderPathUsesWhisperNamingConvention() {
        let path = "/tmp/models/ggml-large-v3-turbo.bin"
        let encoderURL = AppleSiliconInferenceBackend.coreMLEncoderURL(forModelPath: path)

        XCTAssertEqual(
            encoderURL.path,
            "/tmp/models/ggml-large-v3-turbo-encoder.mlmodelc"
        )
    }

    func testHardwareDetectionRequiresRuntimeEvidence() {
        XCTAssertEqual(
            AppleSiliconInferenceBackend.detectHardware(
                fromWhisperDiagnostics: "Core ML model loaded\nuse gpu = 1\nMetal initialized"
            ),
            .appleNeuralEngineAndMetalGPU
        )
        XCTAssertEqual(
            AppleSiliconInferenceBackend.detectHardware(
                fromWhisperDiagnostics: "Core ML model loaded\nuse gpu = 0"
            ),
            .appleNeuralEngine
        )
        XCTAssertEqual(
            AppleSiliconInferenceBackend.detectHardware(
                fromWhisperDiagnostics: "use gpu = 1\nMetal initialized"
            ),
            .metalGPU
        )
        XCTAssertEqual(
            AppleSiliconInferenceBackend.detectHardware(
                fromWhisperDiagnostics: "use gpu = 0"
            ),
            .cpuFallback
        )
    }

    func testTranscriptAccumulatorMergesSlidingWindowOverlap() {
        let accumulator = TranscriptAccumulator()
        XCTAssertEqual(accumulator.append(rawText: "今天要測試語音辨識"), "今天要測試語音辨識")
        XCTAssertEqual(
            accumulator.append(rawText: "語音辨識是否正常"),
            "今天要測試語音辨識是否正常"
        )
    }

    func testTranscriptAccumulatorReplacesActiveWindowRevision() {
        let accumulator = TranscriptAccumulator()
        XCTAssertEqual(accumulator.append(rawText: "這是一個錯吳"), "這是一個錯吳")
        XCTAssertEqual(accumulator.append(rawText: "這是一個錯誤"), "這是一個錯誤")
    }

    func testSlidingTranscriptFreezesTextLeavingTheAudioWindow() {
        let accumulator = TranscriptAccumulator()
        XCTAssertEqual(
            accumulator.appendSlidingWindow(rawText: "今天要測試語音辨識", windowStartSample: 0),
            "今天要測試語音辨識"
        )
        XCTAssertEqual(
            accumulator.appendSlidingWindow(rawText: "測試語音辨識是否正常", windowStartSample: 8_000),
            "今天要測試語音辨識是否正常"
        )
    }

    func testSlidingTranscriptAllowsRevisionBeforeWindowAdvances() {
        let accumulator = TranscriptAccumulator()
        _ = accumulator.appendSlidingWindow(rawText: "這是一個錯吳", windowStartSample: 0)
        XCTAssertEqual(
            accumulator.appendSlidingWindow(rawText: "這是一個錯誤", windowStartSample: 0),
            "這是一個錯誤"
        )
    }
    
    // TC-C3: Voice Activity Detection (VAD) state events test
    func testVADSilenceDetection() {
        let vad = VADDetector(energyThreshold: 0.05, silenceDurationThreshold: 0.5)
        let spy = VADEventSpy()
        vad.delegate = spy
        
        let now = Date()
        
        // 1. Speech start
        vad.processAudioLevel(0.1, at: now)
        XCTAssertEqual(spy.events.first, .speechStarted)
        
        // 2. Silence for 0.6s (exceeding 0.5s threshold)
        let later = now.addingTimeInterval(0.6)
        vad.processAudioLevel(0.01, at: later)
        
        XCTAssertTrue(spy.events.contains { event in
            if case .speechEnded = event { return true }
            return false
        })
    }
}

final class VADEventSpy: VADDetectorDelegate {
    var events: [VADEvent] = []
    
    func vadDetector(_ detector: VADDetector, didEmitEvent event: VADEvent) {
        events.append(event)
    }
}
