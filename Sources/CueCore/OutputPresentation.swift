// How the output window is shown; window and off exist for debugging in rehearsal only.
public enum OutputPresentation: CaseIterable, Sendable {
    case fullscreen, window, off

    // Concert always puts the picture on the projector, whatever rehearsal asked for.
    public static func effective(requested: OutputPresentation, mode: Mode) -> OutputPresentation {
        mode == .concert ? .fullscreen : requested
    }
}
