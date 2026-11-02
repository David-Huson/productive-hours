import Testing
@testable import ActivityCore

@Test(arguments: ProductivityClass.allCases, [ActivityState.active, .passive, .inactive, .unknown])
func productiveCreditRequiresBothDimensions(productivity: ProductivityClass, activity: ActivityState) {
    let classification = ActivityClassification(productivity: productivity, activity: activity)
    let expected: Bool
    switch (productivity, activity) {
    case (.productive, .active), (.productive, .passive): expected = true
    default: expected = false
    }
    #expect(classification.creditsProductiveTime == expected)
}

@Test func passiveProductiveAndUnproductiveRemainDistinct() {
    let meeting = ActivityClassification(productivity: .productive, activity: .passive)
    let leisure = ActivityClassification(productivity: .unproductive, activity: .passive)
    #expect(meeting != leisure)
    #expect(meeting.creditsProductiveTime)
    #expect(!leisure.creditsProductiveTime)
}

@Test func unclassifiedPassiveTimeIsNotCredited() {
    let classification = ActivityClassification(activity: .passive)
    #expect(classification.productivity == .undefined)
    #expect(!classification.creditsProductiveTime)
}
