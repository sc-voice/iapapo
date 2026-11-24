//
//  VATests.swift
//  VATests
//
//  Created by Visakha on 10/29/26.
//

import Testing
import VACore
@testable import VA

/// Checks the icon bar's targets, which come from the transition table.
struct AgentViewTests {

    @Test func inactiveOffersListening() {
        #expect(AgentView.permittedNext(from: .inactive, micAvailable: true) == [.listening])
    }

    @Test func listeningOffersSpeakingIdleAndInactive() {
        #expect(AgentView.permittedNext(from: .listening, micAvailable: true)
            == [.speaking, .idle, .inactive])
    }

    @Test func thinkingIsNeverOffered() {
        #expect(!AgentView.permittedNext(from: .listening, micAvailable: true).contains(.thinking))
    }

    @Test func idleIsHiddenWithoutMic() {
        #expect(AgentView.permittedNext(from: .listening, micAvailable: false)
            == [.speaking, .inactive])
    }
}
