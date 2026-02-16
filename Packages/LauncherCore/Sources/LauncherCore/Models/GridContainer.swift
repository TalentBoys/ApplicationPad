//
//  GridContainer.swift
//  LauncherCore
//
//  Protocol and types for grid containers (root launcher and folders)
//

import Foundation

/// Rules that govern container behavior
public struct ContainerRules: Sendable {
    /// Whether this container allows creating/containing folders
    public let allowsFolder: Bool

    public init(allowsFolder: Bool) {
        self.allowsFolder = allowsFolder
    }
}

/// Layout configuration for a grid
public struct GridLayout: Sendable {
    public let rows: Int
    public let columns: Int
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let iconSize: CGSize

    public init(rows: Int, columns: Int, cellWidth: CGFloat, cellHeight: CGFloat, iconSize: CGSize) {
        self.rows = rows
        self.columns = columns
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.iconSize = iconSize
    }

    /// Total slots per page
    public var slotsPerPage: Int {
        rows * columns
    }

    /// Get frame for a position
    public func frame(for position: GridPosition) -> CGRect {
        CGRect(
            x: CGFloat(position.column) * cellWidth,
            y: CGFloat(position.row) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )
    }

    /// Get position from a point (hit test)
    public func hitTestPosition(location: CGPoint) -> GridPosition {
        let col = max(0, min(columns - 1, Int(location.x / cellWidth)))
        let row = max(0, min(rows - 1, Int(location.y / cellHeight)))
        return GridPosition(row: row, column: col)
    }

    /// Get icon frame within a slot (centered)
    public func iconFrame(in slotFrame: CGRect) -> CGRect {
        CGRect(
            x: slotFrame.minX + (slotFrame.width - iconSize.width) / 2,
            y: slotFrame.minY + (slotFrame.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
    }
}

/// Protocol for grid containers (root launcher or folder)
public protocol GridContainer: AnyObject, Sendable {
    var pages: [Page] { get set }
    var layout: GridLayout { get }
    var rules: ContainerRules { get }
}

extension GridContainer {
    /// Total number of pages
    public var pageCount: Int {
        pages.count
    }

    /// Get page at index
    public func page(at index: Int) -> Page? {
        guard index >= 0, index < pages.count else { return nil }
        return pages[index]
    }

    /// Find position of content by ID across all pages
    public func findPosition(of id: UUID) -> (pageIndex: Int, position: GridPosition)? {
        for (pageIndex, page) in pages.enumerated() {
            if let position = page.position(of: id) {
                return (pageIndex, position)
            }
        }
        return nil
    }

    /// Calculate drop intent based on local point within a slot
    public func calculateDropIntent(
        at localPoint: CGPoint,
        in slot: GridSlot,
        slotSize: CGSize,
        iconSize: CGSize
    ) -> DropIntent {
        // If slot is empty, directly occupy it
        if slot.isEmpty {
            return .intoEmpty(position: slot.position)
        }

        // Calculate icon rect (centered in slot)
        let iconRect = CGRect(
            x: (slotSize.width - iconSize.width) / 2,
            y: (slotSize.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )

        // If inside icon area -> trigger merge
        if iconRect.contains(localPoint) {
            return .merge(target: slot.position)
        }

        // If above or below icon area
        if localPoint.y < iconRect.minY || localPoint.y > iconRect.maxY {
            // Check if in left/right corners
            if localPoint.x < iconRect.minX {
                return .insertBefore(target: slot.position)
            } else if localPoint.x > iconRect.maxX {
                return .insertAfter(target: slot.position)
            } else {
                // Directly above or below - no action (treat as intoEmpty for now)
                return .intoEmpty(position: slot.position)
            }
        }

        // Left or right edge
        if localPoint.x < iconRect.minX {
            return .insertBefore(target: slot.position)
        } else {
            return .insertAfter(target: slot.position)
        }
    }

    /// Check if merge is allowed
    public func canMerge(dragged: SlotContent, target: SlotContent) -> Bool {
        guard rules.allowsFolder else { return false }
        // Can merge app with app or app with folder
        // Cannot merge folder with folder
        if dragged.isFolder && target.isFolder { return false }
        return true
    }

    /// Insert content at position with cross-page overflow handling
    public func insertWithOverflow(_ content: SlotContent, at pageIndex: Int, position: GridPosition) {
        var carrying: SlotContent? = content
        var currentPageIndex = pageIndex

        // Insert at specific position on first page
        if currentPageIndex < pages.count {
            carrying = pages[currentPageIndex].insertAndPush(content, at: position)
            currentPageIndex += 1
        }

        // Handle overflow to subsequent pages
        while let overflow = carrying {
            if currentPageIndex >= pages.count {
                // Create new page
                pages.append(Page.empty(rows: layout.rows, columns: layout.columns))
            }
            carrying = pages[currentPageIndex].insertAndPush(overflow, at: GridPosition(row: 0, column: 0))
            currentPageIndex += 1
        }
    }

    /// Remove empty trailing pages (keep at least one page)
    public func trimEmptyPages() {
        while pages.count > 1 && pages.last?.isCompletelyEmpty == true {
            pages.removeLast()
        }
    }
}
