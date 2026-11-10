import CueCore
import Testing

struct HexColourTests {
    @Test(arguments: [("#E53935", 0xE53935), ("e53935", 0xE53935), ("#444", 0x444444), ("#7a4aff", 0x7A4AFF)])
    func parses(text: String, rgb: UInt32) {
        #expect(HexColour.rgb(from: text) == rgb)
    }

    @Test(arguments: ["", "#", "#12", "red", "#GGGGGG", "#1234567", "#+12345", "##444"])
    func rejects(text: String) {
        #expect(HexColour.rgb(from: text) == nil)
    }
}
