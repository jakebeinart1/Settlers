import Foundation

/// Explicit validated coastlines replace compact greedy growth at the retry boundary.
/// Their shallow shape lets a sailing ship discover every interior without landing first.
enum NavalFallback {
    static func groups(for family: NavalMapFamily) -> [[HexCoordinate]] {
        let tuples: [[(Int, Int)]]
        switch family {
        case .archipelago:
            tuples = [
                [(-5, 0), (-4, -2), (-5, -1), (-6, 0), (-6, 1), (-6, -1), (-7, 0)],
                [(2, -6), (1, -6), (0, -6), (-1, -5), (1, -7), (0, -7), (-1, -6)],
                [(5, 0), (5, 1), (6, 0), (6, -1), (6, 1), (7, 0), (7, -1)],
                [(-1, 5), (-2, 6), (-1, 6), (0, 6), (-1, 7), (0, 7), (1, 6)],
            ]
        case .peninsula:
            tuples = [
                [(-5, 0), (-2, -4), (-3, -3), (-4, -2), (-5, -1), (-6, 0), (-6, 1),
                 (-2, -5), (-3, -4), (-4, -3), (-5, -2), (-6, -1), (-7, 0), (-7, 1)],
                [(0, -5), (1, -6), (0, -6), (0, -7)],
                [(5, 0), (4, 2), (5, 1), (6, 0), (6, -1), (7, 0), (7, -1)],
                [(0, 5), (-1, 6), (0, 6)],
            ]
        case .twinIslands:
            tuples = [
                [(4, 1), (5, 0), (5, -1), (5, 1), (6, 0), (6, -1), (6, -2), (6, 1), (7, 0), (7, -1), (7, -2)],
                [(0, 6), (1, 5), (-1, 7)],
                [(-4, -1), (-5, 0), (-4, -2), (-5, -1), (-6, 0), (-6, 1), (-6, 2), (-6, -1), (-7, 0), (-7, 1), (-7, 2)],
                [(0, -6), (-1, -5), (-2, -4)],
            ]
        }
        return tuples.map { $0.map { HexCoordinate(q: $0.0, r: $0.1) }.sorted() }
    }
}
