import XCTest
@testable import ButterflyCore

final class ModelManagerTests: XCTestCase {
    var manager: ModelManager!
    
    override func setUp() {
        super.setUp()
        manager = ModelManager.shared
    }
    
    func testWhitelistPriorityRanking() {
        let models = ModelManager.defaultModels
        XCTAssertGreaterThanOrEqual(models.count, 6, "Must define at least 6 prioritized whitelist models")
        
        // Rank 1 must be Whisper Large-v3-Turbo
        XCTAssertEqual(models[0].id, "whisper-large-v3-turbo")
        XCTAssertEqual(models[0].displayName, "Whisper Large-v3-Turbo (809M)")
        
        // Rank 6 fallback must be Apple Native
        XCTAssertEqual(models.last?.id, "apple-speech-native")
    }
    
    func testFormattedSizes() {
        let largeTurbo = ModelManager.defaultModels[0]
        XCTAssertEqual(largeTurbo.formattedSize, "1.54 GB")
        
        let tiny = ModelManager.defaultModels.first { $0.id == "whisper-tiny" }
        XCTAssertEqual(tiny?.formattedSize, "75.0 MB")
    }
    
    func testGetBestAvailableModel() {
        let best = manager.getBestAvailableModel()
        XCTAssertFalse(best.id.isEmpty)
        XCTAssertFalse(best.displayName.isEmpty)
    }

    func testRuntimeModelSupportMatchesImplementedBackends() {
        let whisper = ModelManager.defaultModels.first { $0.id == "whisper-large-v3-turbo" }!
        let senseVoice = ModelManager.defaultModels.first { $0.id == "sensevoice-small" }!
        let appleSpeech = ModelManager.defaultModels.first { $0.id == "apple-speech-native" }!

        XCTAssertTrue(ModelManager.isRuntimeSupported(whisper))
        XCTAssertFalse(ModelManager.isRuntimeSupported(senseVoice))
        XCTAssertTrue(ModelManager.isRuntimeSupported(appleSpeech))
    }
}
