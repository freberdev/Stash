import Foundation
import Testing
@testable import StashCore

@Suite struct RetentionTests {
    @Test func neverMeansNoLimit() {
        #expect(Retention.never.interval == nil)
    }

    @Test func theOthersAreCountedInDays() {
        let day: TimeInterval = 86_400
        #expect(Retention.oneDay.interval == day)
        #expect(Retention.oneWeek.interval == 7 * day)
        #expect(Retention.oneMonth.interval == 30 * day)
    }
}
