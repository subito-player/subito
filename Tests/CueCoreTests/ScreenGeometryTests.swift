import Foundation
import Testing

@testable import CueCore

@Suite struct ScreenGeometryTests {
    // Quartz layout of the show Mac: laptop panel at the origin, projector to its right starting at x 1512.
    let laptop = CGRect(origin: CGPoint(x: 0, y: 0), size: CGSize(width: 1512, height: 982))

    @Test func cursorOnProjectorLandsOnLaptopNotOnSharedEdge() {
        let point = ScreenGeometry.nearestPoint(to: CGPoint(x: 1800, y: 400), inAnyOf: [laptop])
        #expect(point?.x == 1511 && point?.y == 400)
    }

    @Test func cursorBeyondLaptopCornerClampsToCorner() {
        let point = ScreenGeometry.nearestPoint(to: CGPoint(x: 2000, y: 1020), inAnyOf: [laptop])
        #expect(point?.x == 1511 && point?.y == 981)
    }

    @Test func picksTheClosestOfSeveralControlScreens() {
        let above = CGRect(origin: CGPoint(x: 1600, y: -1130), size: CGSize(width: 1920, height: 1080))
        let point = ScreenGeometry.nearestPoint(to: CGPoint(x: 2500, y: -40), inAnyOf: [laptop, above])
        #expect(point?.x == 2500 && point?.y == -51)
    }
}
