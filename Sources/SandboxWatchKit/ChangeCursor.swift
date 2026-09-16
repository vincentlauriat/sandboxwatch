import Foundation

public struct CursorScan: Equatable {
    /// Newest first, as the API returns them.
    public let newEvents: [ChangeEvent]
    /// True when the page did not reach back as far as the mark: events fell off the end and
    /// the caller must widen the limit and ask again.
    public let overflowed: Bool
    /// Where to move the cursor once the caller has consumed `newEvents`.
    public let newest: ChangeMark?
}

public enum ChangeCursor {
    /// Decides what is new in a page of change events.
    ///
    /// `/api/v1/changes` returns newest first and caps at 500. Two properties matter here:
    ///
    /// - the mark is `(at, type, subject)`, because timestamps tie;
    /// - a page that never reaches the mark means events were lost, and that must be a signal
    ///   rather than a silent truncation.
    public static func scan(page: [ChangeEvent], since mark: ChangeMark?) -> CursorScan {
        let newest = page.first?.mark

        // First run: establish where we are, announce nothing. Otherwise adding a sandbox
        // would replay its whole history as notifications.
        guard let mark else {
            return CursorScan(newEvents: [], overflowed: false, newest: newest)
        }

        if let index = page.firstIndex(where: { $0.mark == mark }) {
            return CursorScan(newEvents: Array(page[0..<index]), overflowed: false, newest: newest)
        }

        guard let oldest = page.last else {
            return CursorScan(newEvents: [], overflowed: false, newest: nil)
        }

        if oldest.at > mark.at {
            // Everything in the page is newer than the mark and the mark is not in it: the
            // page did not reach far enough back, so something between them was not returned.
            return CursorScan(newEvents: page, overflowed: true, newest: newest)
        }

        // We reached back past the mark's instant, so nothing was lost. The marked event
        // itself is simply gone — pruned, or the mark predates the log.
        //
        // This is the one path that compares time alone, and it therefore drops any sibling
        // that shared the marked event's instant. That is deliberate: once the marked event is
        // gone there is nothing left to order its ties against, and re-announcing a change the
        // operator has already seen is the worse of the two errors here.
        return CursorScan(
            newEvents: page.filter { $0.at > mark.at }, overflowed: false, newest: newest)
    }

    /// The widening ladder used after an overflow. `nil` means the server's ceiling is
    /// reached and the caller must report the gap instead of asking again.
    public static func nextLimit(after limit: Int) -> Int? {
        switch limit {
        case ..<200: return 200
        case ..<500: return 500
        default: return nil
        }
    }
}
