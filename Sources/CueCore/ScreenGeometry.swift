import Foundation

public enum ScreenGeometry {
    // Far edges are exclusive: x == origin.x + width already belongs to the screen on the right.
    public static func nearestPoint(to point: CGPoint, inAnyOf rects: [CGRect]) -> CGPoint? {
        let candidates = rects.filter { $0.size.width >= 1 && $0.size.height >= 1 }.map { rect in
            CGPoint(
                x: min(max(point.x, rect.origin.x), rect.origin.x + rect.size.width - 1),
                y: min(max(point.y, rect.origin.y), rect.origin.y + rect.size.height - 1)
            )
        }
        return candidates.min { distance($0, point) < distance($1, point) }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}
