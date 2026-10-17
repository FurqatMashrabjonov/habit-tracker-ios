import Testing
@testable import HabitDomain

@Suite struct PriorityTests {
    @Test func tagIsStrippedAndTheLastOneWins() {
        let r = Priority.parse("Pay rent p1")
        #expect(r.title == "Pay rent" && r.priority == 1)
        let two = Priority.parse("p3 Call mom P2")
        #expect(two.title == "Call mom" && two.priority == 2)
    }

    @Test func plainTitlesAndLoneTagsAreLeftAlone() {
        #expect(Priority.parse("Buy p12 batteries").priority == nil)
        #expect(Priority.parse("p1").title == "p1")
        #expect(Priority.parse("p1").priority == nil)
        #expect(Priority.parse("Pay rent p5").priority == nil)
    }

    @Test func inkDepthPerPriority() {
        #expect(Priority.alpha(1) == 1)
        #expect(Priority.alpha(2) == 0.6)
        #expect(Priority.alpha(3) == 0.35)
        #expect(Priority.alpha(Priority.none) == nil)
    }
}
