import Testing

@testable import CueCore

private let laptop = DisplayInfo(id: 1, builtIn: true)
private let projector = DisplayInfo(id: 2)
private let monitor = DisplayInfo(id: 3)

@Suite struct DisplayRolesTests {
    @Test func laptopControlsAndTheProjectorIsTheOutput() {
        let roles = DisplayRoles(displays: [laptop, projector], main: 2, preferred: nil)
        #expect(roles == DisplayRoles(displays: [projector, laptop], main: 1, preferred: nil))
        #expect((roles.control, roles.output, roles.candidates, roles.mirror) == (1, 2, [2], nil))
    }

    @Test func withoutABuiltInPanelTheMainDisplayControls() {
        let lidClosed = DisplayRoles(displays: [projector, monitor], main: 3, preferred: nil)
        #expect((lidClosed.control, lidClosed.output) == (3, 2))
        let other = DisplayRoles(displays: [projector, monitor], main: 2, preferred: nil)
        #expect((other.control, other.output) == (2, 3))
    }

    @Test func aSingleDisplayIsNeverTheOutput() {
        #expect(DisplayRoles(displays: [monitor], main: 3, preferred: 3).output == nil)
        #expect(DisplayRoles(displays: [laptop], main: 1, preferred: nil).output == nil)
    }

    @Test func aPickedDisplayWinsUnlessItIsTheControlScreen() {
        let all = [laptop, projector, monitor]
        #expect(DisplayRoles(displays: all, main: 1, preferred: 3).output == 3)
        #expect(DisplayRoles(displays: all, main: 1, preferred: 1).output == 2)
        #expect(DisplayRoles(displays: all, main: 1, preferred: 9).output == 2)
    }

    @Test func aSavedPickThatBecameMainKeepsTheOutputAndAnotherDisplayControls() {
        // Lid closed, monitor and projector; macOS made the projector main, and it is the saved pick.
        let roles = DisplayRoles(displays: [monitor, projector], main: 2, preferred: 2)
        #expect((roles.control, roles.output) == (3, 2))
        let mirroredMain = DisplayRoles(
            displays: [DisplayInfo(id: 2), DisplayInfo(id: 4, mirrorOf: 2), monitor], main: 4, preferred: 2)
        #expect((mirroredMain.control, mirroredMain.output) == (3, 2))
        // With the lid open the panel controls, whatever is main.
        #expect(DisplayRoles(displays: [laptop, projector], main: 2, preferred: 2).control == 1)
        // Nothing else to control from: the pick cannot be the output.
        #expect(DisplayRoles(displays: [projector], main: 2, preferred: 2).output == nil)
    }

    @Test func aMirrorOfTheControlScreenIsNeverAnOutput() {
        let mirrored = DisplayInfo(id: 2, mirrorOf: 1, active: false)
        let roles = DisplayRoles(displays: [laptop, mirrored], main: 1, preferred: 2)
        #expect((roles.output, roles.candidates, roles.mirror) == (nil, [], 2))
        let withMonitor = DisplayRoles(displays: [laptop, mirrored, monitor], main: 1, preferred: nil)
        #expect((withMonitor.output, withMonitor.mirror) == (3, 2))
    }
}
