import Testing
@testable import VACore

@Test func inactiveReleasesSessionToSoloAmbient() {
    #expect(sessionPolicy(for: .inactive)
        == SessionPolicy(category: .soloAmbient, active: false))
}

@Test func everyOtherStateActivatesPlayAndRecord() {
    for state in [VAState.idle, .listening, .thinking, .speaking] {
        #expect(sessionPolicy(for: state)
            == SessionPolicy(category: .playAndRecord, active: true))
    }
}
