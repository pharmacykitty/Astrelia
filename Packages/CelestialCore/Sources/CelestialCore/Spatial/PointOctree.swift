import simd

/// An immutable octree over a fixed set of 3D points, built once and queried many
/// times. It exists to make the Galaxy Map scale: instead of projecting every one of
/// ~10⁵ catalogue stars each frame, the renderer asks the tree which points fall
/// inside the view frustum and only touches those. Picking (tap-to-select) uses the
/// same query to scan a small candidate set rather than the whole catalogue.
///
/// Pure value type, `Sendable`, no UIKit/SwiftUI — it lives in `CelestialCore` so it
/// can be unit-tested against brute force and reused by the eventual Metal renderer.
///
/// Coordinates are arbitrary (the Galaxy Map uses parsecs, Sun at origin), as long as
/// the same space is used for the points and the query planes.
public struct PointOctree: Sendable {

    /// A node is a cube (`center` ± `half` on each axis). Internal nodes reference up
    /// to 8 children by index (`-1` = empty octant); leaves reference a contiguous
    /// run of point indices in `leafIndices`.
    private struct Node: Sendable {
        var center: SIMD3<Float>
        var half: Float
        var children: [Int32]?     // 8 child node indices, or nil for a leaf
        var start: Int32           // leaf: first index into leafIndices
        var count: Int32           // leaf: number of point indices
    }

    private let nodes: [Node]
    private let leafIndices: [Int]
    private let root: Int32
    public let pointCount: Int

    /// Builds the tree. `maxLeaf` caps points per leaf; `maxDepth` bounds recursion so
    /// coincident points can't recurse forever.
    public init(points: [SIMD3<Float>], maxLeaf: Int = 24, maxDepth: Int = 18) {
        pointCount = points.count
        guard !points.isEmpty else {
            nodes = []; leafIndices = []; root = -1; return
        }

        // Root cube: the bounding cube of all points (a cube keeps the octant split
        // trivial; a slightly loose fit is fine for culling).
        var lo = points[0], hi = points[0]
        for p in points {
            lo = simd_min(lo, p)
            hi = simd_max(hi, p)
        }
        let center = (lo + hi) * 0.5
        let extent = hi - lo
        let half = max(extent.x, max(extent.y, extent.z)) * 0.5 + 1e-3

        var builder = Builder(points: points, maxLeaf: max(1, maxLeaf), maxDepth: maxDepth)
        root = builder.build(Array(points.indices), center: center, half: half, depth: 0)
        nodes = builder.nodes
        leafIndices = builder.leafIndices
    }

    /// Returns the indices of all points that *may* lie inside the convex region
    /// defined by `planes` (a point is inside when `dot(plane.xyz, p) + plane.w >= 0`
    /// for every plane). Conservative: a straddling leaf contributes all its points,
    /// so callers should still do their own fine test (the renderer's screen-bounds
    /// cull, the picker's distance test). Whole subtrees fully inside are added
    /// without per-point work — the source of the speed-up.
    public func query(planes: [SIMD4<Float>]) -> [Int] {
        var out: [Int] = []
        guard root >= 0 else { return out }
        out.reserveCapacity(min(pointCount, 4096))
        visit(root, planes, &out)
        return out
    }

    private func visit(_ index: Int32, _ planes: [SIMD4<Float>], _ out: inout [Int]) {
        let node = nodes[Int(index)]
        var fullyInside = true
        for plane in planes {
            let n = SIMD3(plane.x, plane.y, plane.z)
            let sign = SIMD3<Float>(n.x >= 0 ? 1 : -1, n.y >= 0 ? 1 : -1, n.z >= 0 ? 1 : -1)
            // Positive vertex (farthest along +n): if it's behind the plane, the whole
            // cube is outside → prune.
            if simd_dot(n, node.center + node.half * sign) + plane.w < 0 { return }
            // Negative vertex behind the plane ⇒ the cube straddles this plane.
            if simd_dot(n, node.center - node.half * sign) + plane.w < 0 { fullyInside = false }
        }
        if fullyInside {
            addSubtree(index, &out)
        } else if let children = node.children {
            for c in children where c >= 0 { visit(c, planes, &out) }
        } else {
            for k in node.start..<(node.start + node.count) { out.append(leafIndices[Int(k)]) }
        }
    }

    /// Adds every point under `index` without any plane tests (the node is known to be
    /// fully inside).
    private func addSubtree(_ index: Int32, _ out: inout [Int]) {
        let node = nodes[Int(index)]
        if let children = node.children {
            for c in children where c >= 0 { addSubtree(c, &out) }
        } else {
            for k in node.start..<(node.start + node.count) { out.append(leafIndices[Int(k)]) }
        }
    }

    /// Mutable scratch used only during construction.
    private struct Builder {
        let points: [SIMD3<Float>]
        let maxLeaf: Int
        let maxDepth: Int
        var nodes: [Node] = []
        var leafIndices: [Int] = []

        mutating func build(_ idxs: [Int], center: SIMD3<Float>, half: Float, depth: Int) -> Int32 {
            if idxs.count <= maxLeaf || depth >= maxDepth {
                let start = Int32(leafIndices.count)
                leafIndices.append(contentsOf: idxs)
                nodes.append(Node(center: center, half: half, children: nil, start: start, count: Int32(idxs.count)))
                return Int32(nodes.count - 1)
            }
            // Partition into 8 octants about the cube centre.
            var buckets = [[Int]](repeating: [], count: 8)
            for i in idxs {
                let p = points[i]
                var octant = 0
                if p.x >= center.x { octant |= 1 }
                if p.y >= center.y { octant |= 2 }
                if p.z >= center.z { octant |= 4 }
                buckets[octant].append(i)
            }
            let childHalf = half * 0.5
            var childIDs = [Int32](repeating: -1, count: 8)
            for o in 0..<8 where !buckets[o].isEmpty {
                let cc = center + childHalf * SIMD3<Float>(o & 1 == 0 ? -1 : 1,
                                                           o & 2 == 0 ? -1 : 1,
                                                           o & 4 == 0 ? -1 : 1)
                childIDs[o] = build(buckets[o], center: cc, half: childHalf, depth: depth + 1)
            }
            nodes.append(Node(center: center, half: half, children: childIDs, start: 0, count: 0))
            return Int32(nodes.count - 1)
        }
    }
}
