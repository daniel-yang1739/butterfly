import XCTest
@testable import ButterflyCore

final class StateMachineTests: XCTestCase {
    
    func testStateMachineEndToEndFlow() async {
        let rawInput = "这是测试React代码"
        let backend = MockInferenceBackend(mockResult: TranscriptionResult(rawText: rawInput))
        let stateMachine = ButterflyStateMachine(backend: backend)
        
        let spy = StateMachineSpy()
        stateMachine.delegate = spy
        
        // 1. Start listening
        await stateMachine.startListening()
        XCTAssertEqual(stateMachine.currentState, .listening(audioLevel: 0.0))
        
        // 2. Simulate microphone audio input
        stateMachine.audioCapture.appendSamples([0.2, 0.4, 0.6, 0.3])
        
        // 3. Stop listening and process
        await stateMachine.stopAndProcess()
        
        // Verify final output converted to Traditional Chinese with Pangu spacing
        XCTAssertEqual(spy.lastProducedText, "這是測試 React 程式碼")
    }
}

final class StateMachineSpy: ButterflyStateMachineDelegate {
    var states: [ButterflyState] = []
    var lastProducedText: String?
    
    func stateMachine(_ stateMachine: ButterflyStateMachine, didTransitionTo state: ButterflyState) {
        states.append(state)
    }
    
    func stateMachine(_ stateMachine: ButterflyStateMachine, didProduceTranscription text: String) {
        lastProducedText = text
    }
}
