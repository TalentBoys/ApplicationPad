//
//  Page.swift
//  LauncherCore
//
//  A page containing a 2D grid of slots
//

import Foundation

public struct Page: Equatable, Sendable {
    public let rows: Int
    public let columns: Int
    public var slots: [[GridSlot]]  // 2D array [row][column]

    public init(rows: Int, columns: Int) {
        self.rows = rows
        self.columns = columns
        self.slots = (0..<rows).map { row in
            (0..<columns).map { col in
                GridSlot(position: GridPosition(row: row, column: col))
            }
        }
    }

    /// Create an empty page with the specified dimensions
    public static func empty(rows: Int, columns: Int) -> Page {
        Page(rows: rows, columns: columns)
    }

    /// Total number of slots in this page
    public var totalSlots: Int {
        rows * columns
    }

    /// Get slot at position
    public func slot(at position: GridPosition) -> GridSlot? {
        guard position.row >= 0, position.row < rows,
              position.column >= 0, position.column < columns else {
            return nil
        }
        return slots[position.row][position.column]
    }

    /// Get content at position
    public func content(at position: GridPosition) -> SlotContent? {
        slot(at: position)?.content
    }

    /// Set content at position
    public mutating func setContent(_ content: SlotContent, at position: GridPosition) {
        guard position.row >= 0, position.row < rows,
              position.column >= 0, position.column < columns else {
            return
        }
        slots[position.row][position.column].content = content
    }

    /// Get all positions in linear order (row-major)
    public func linearPositions() -> [GridPosition] {
        var result: [GridPosition] = []
        for r in 0..<rows {
            for c in 0..<columns {
                result.append(GridPosition(row: r, column: c))
            }
        }
        return result
    }

    /// Get all slots in linear order (row-major)
    public func linearSlots() -> [GridSlot] {
        linearPositions().compactMap { slot(at: $0) }
    }

    /// Get all non-empty contents in linear order
    public func linearContents() -> [SlotContent] {
        linearSlots().map { $0.content }.filter { !$0.isEmpty }
    }

    /// Find the first empty position
    public func firstEmptyPosition() -> GridPosition? {
        for position in linearPositions() {
            if let slot = slot(at: position), slot.isEmpty {
                return position
            }
        }
        return nil
    }

    /// Find position of content by ID
    public func position(of id: UUID) -> GridPosition? {
        for position in linearPositions() {
            if let slot = slot(at: position), slot.content.id == id {
                return position
            }
        }
        return nil
    }

    /// Check if page has any non-empty content
    public var hasContent: Bool {
        linearSlots().contains { !$0.isEmpty }
    }

    /// Check if page is completely empty
    public var isCompletelyEmpty: Bool {
        !hasContent
    }

    /// Count of occupied slots
    public var occupiedCount: Int {
        linearSlots().filter { !$0.isEmpty }.count
    }

    /// Insert content at position, pushing existing content forward
    /// Returns overflow content if pushed beyond page bounds
    public mutating func insertAndPush(_ content: SlotContent, at position: GridPosition) -> SlotContent? {
        let positions = linearPositions()
        guard let startIndex = positions.firstIndex(of: position) else {
            return content
        }

        var carrying: SlotContent? = content
        for i in startIndex..<positions.count {
            let pos = positions[i]
            let current = slots[pos.row][pos.column].content
            slots[pos.row][pos.column].content = carrying ?? .empty
            if current.isEmpty {
                return nil  // Found empty slot, no overflow
            }
            carrying = current
        }

        return carrying  // Return overflow
    }

    /// Remove content at position and compact (pull items backward)
    public mutating func removeAndCompact(at position: GridPosition) -> SlotContent? {
        let positions = linearPositions()
        guard let startIndex = positions.firstIndex(of: position) else {
            return nil
        }

        let removed = slots[position.row][position.column].content

        // Shift all items after this position backward
        for i in startIndex..<(positions.count - 1) {
            let current = positions[i]
            let next = positions[i + 1]
            slots[current.row][current.column].content = slots[next.row][next.column].content
        }

        // Clear the last position
        if let last = positions.last {
            slots[last.row][last.column].content = .empty
        }

        return removed
    }

    /// Clear content at position (make it empty)
    public mutating func clear(at position: GridPosition) {
        guard position.row >= 0, position.row < rows,
              position.column >= 0, position.column < columns else {
            return
        }
        slots[position.row][position.column].content = .empty
    }
}
