import Testing
import simd
@testable import CelestialCore

@Suite struct PointOctreeTests {

    /// Axis-aligned box as 6 half-space planes (inside ⇔ dot(n,p)+w ≥ 0).
    private func boxPlanes(min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> [SIMD4<Float>] {
        [SIMD4( 1, 0, 0, -lo.x), SIMD4(-1, 0, 0, hi.x),
         SIMD4( 0, 1, 0, -lo.y), SIMD4( 0, -1, 0, hi.y),
         SIMD4( 0, 0, 1, -lo.z), SIMD4( 0, 0, -1, hi.z)]
    }

    private func inside(_ p: SIMD3<Float>, _ planes: [SIMD4<Float>]) -> Bool {
        planes.allSatisfy { simd_dot(SIMD3($0.x, $0.y, $0.z), p) + $0.w >= 0 }
    }

    private func randomPoints(_ n: Int, seed: UInt64) -> [SIMD3<Float>] {
        var state = seed
        func next() -> Float {                       // xorshift → [-500, 500)
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return Float(state % 1000) - 500
        }
        return (0..<n).map { _ in SIMD3(next(), next(), next()) }
    }

    /// The core invariant: the query must never drop a point that truly lies inside
    /// the region (it may be conservatively over-inclusive, never under-inclusive).
    @Test func queryContainsEveryTrulyInsidePoint() {
        let points = randomPoints(5000, seed: 0xC0FFEE)
        let tree = PointOctree(points: points)
        let planes = boxPlanes(min: SIMD3(-120, -200, -50), max: SIMD3(180, 60, 240))

        let result = Set(tree.query(planes: planes))
        let bruteInside = points.indices.filter { inside(points[$0], planes) }

        for i in bruteInside { #expect(result.contains(i)) }      // no false negatives
        #expect(result.allSatisfy { points.indices.contains($0) }) // valid indices only
        // Culling actually happened — we didn't just return everything.
        #expect(result.count < points.count)
        #expect(result.count >= bruteInside.count)
    }

    /// A region enclosing every point returns all of them, exactly once.
    @Test func queryAllInsideReturnsEverythingWithoutDuplicates() {
        let points = randomPoints(2000, seed: 42)
        let tree = PointOctree(points: points)
        let result = tree.query(planes: boxPlanes(min: SIMD3(-1000, -1000, -1000),
                                                  max: SIMD3(1000, 1000, 1000)))
        #expect(result.count == points.count)
        #expect(Set(result).count == points.count)               // no duplicates
    }

    /// A region with no points returns nothing.
    @Test func queryFullyOutsideReturnsEmpty() {
        let points = randomPoints(2000, seed: 7)
        let tree = PointOctree(points: points)
        let result = tree.query(planes: boxPlanes(min: SIMD3(5000, 5000, 5000),
                                                  max: SIMD3(6000, 6000, 6000)))
        #expect(result.isEmpty)
    }

    @Test func emptyTreeIsSafe() {
        let tree = PointOctree(points: [])
        #expect(tree.pointCount == 0)
        #expect(tree.query(planes: boxPlanes(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))).isEmpty)
    }

    /// Many coincident points must not blow the depth cap or lose any.
    @Test func coincidentPointsAreAllRetained() {
        let points = [SIMD3<Float>](repeating: SIMD3(3, 3, 3), count: 500)
        let tree = PointOctree(points: points, maxLeaf: 8, maxDepth: 6)
        let result = tree.query(planes: boxPlanes(min: SIMD3(0, 0, 0), max: SIMD3(6, 6, 6)))
        #expect(result.count == 500)
    }
}
