import Foundation

/// Lane layout for the commit graph: newest-first topo-ordered commits in,
/// rows with a dot column and edge segments out. Lane indices stay stable;
/// a freed lane is reused by the next allocation, so the graph stays narrow.
struct GitGraph {
    struct Row: Identifiable {
        let commit: GitService.Commit
        /// Lane holding this commit's dot.
        let column: Int
        /// Lanes entering from above that converge on the dot.
        let incoming: [Int]
        /// Lanes passing straight through this row.
        let through: [Int]
        /// Lanes the dot connects down to: first parent, then merge parents.
        let outgoing: [Int]
        var id: String { commit.sha }
    }

    let rows: [Row]
    let maxLanes: Int

    init(commits: [GitService.Commit]) {
        var lanes: [String?] = []
        var rows: [Row] = []
        var maxLanes = 0

        for commit in commits {
            let lanesBefore = lanes
            let waiting = lanes.indices.filter { lanes[$0] == commit.sha }

            let column: Int
            if let first = waiting.first {
                column = first
                for index in waiting.dropFirst() { lanes[index] = nil }
            } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                column = free
            } else {
                lanes.append(nil)
                column = lanes.count - 1
            }

            let through = lanesBefore.indices.filter {
                lanesBefore[$0] != nil && $0 != column && !waiting.contains($0)
            }

            var outgoing: [Int] = []
            if let firstParent = commit.parents.first {
                lanes[column] = firstParent
                outgoing.append(column)
            } else {
                lanes[column] = nil
            }
            for parent in commit.parents.dropFirst() {
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    outgoing.append(existing)
                } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[free] = parent
                    outgoing.append(free)
                } else {
                    lanes.append(parent)
                    outgoing.append(lanes.count - 1)
                }
            }

            while let last = lanes.last, last == nil { lanes.removeLast() }
            maxLanes = max(maxLanes, max(lanes.count, column + 1))
            rows.append(Row(commit: commit, column: column, incoming: waiting, through: through, outgoing: outgoing))
        }

        self.rows = rows
        self.maxLanes = maxLanes
    }
}
