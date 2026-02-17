//
//  HitTestTypes.swift
//  LauncherCore
//
//  Types for hit testing during drag operations
//

import Foundation

// MARK: - Cell Region (鼠标在格子内的位置)

/// The region within a cell where the cursor is located
/// Based on icon size, divides the cell into 9 regions
public enum CellRegion: Equatable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case center        // Inside icon area
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

// MARK: - Cell Coordinate (格子坐标)

/// Represents a cell's position in the grid
public struct CellCoordinate: Equatable, Sendable {
    public let page: Int
    public let row: Int
    public let column: Int

    public init(page: Int, row: Int, column: Int) {
        self.page = page
        self.row = row
        self.column = column
    }

    /// Convert to linear index
    public func toIndex(columnsCount: Int, appsPerPage: Int) -> Int {
        return page * appsPerPage + row * columnsCount + column
    }

    /// Create from linear index
    public static func fromIndex(_ index: Int, columnsCount: Int, rowsCount: Int, appsPerPage: Int) -> CellCoordinate {
        let page = index / appsPerPage
        let indexInPage = index % appsPerPage
        let row = indexInPage / columnsCount
        let column = indexInPage % columnsCount
        return CellCoordinate(page: page, row: row, column: column)
    }
}

// MARK: - Hit Position Result (位置判定结果)

/// Result of hit testing - where is the cursor?
public struct HitPositionResult: Equatable, Sendable {
    /// Which page the cursor is on
    public let page: Int

    /// Which cell the cursor is in (nil if not in any cell)
    public let cell: CellCoordinate?

    /// Where within the cell the cursor is (nil if cell is nil)
    public let region: CellRegion?

    public init(page: Int, cell: CellCoordinate?, region: CellRegion?) {
        self.page = page
        self.cell = cell
        self.region = region
    }

    /// Convenience for when cursor is not in any cell
    public static func notInCell(page: Int) -> HitPositionResult {
        return HitPositionResult(page: page, cell: nil, region: nil)
    }
}

// MARK: - Drag Operation (拖拽操作类型)

/// The type of operation to perform based on cursor position
public enum DragOperation: Equatable, Sendable {
    /// No operation (cursor not in valid position)
    case none

    /// Place into an empty cell
    case placeInEmpty

    /// Insert to the left of target, shift target and others right
    case insertLeft

    /// Insert to the right of target, shift others right
    case insertRight

    /// Insert above target, shift target and others down
    case insertAbove

    /// Insert below target, shift others down
    case insertBelow

    /// Merge with target (create folder or add to folder)
    case merge
}

// MARK: - Grid Layout Parameters

/// Parameters describing the grid layout (for pure functions)
public struct GridLayoutParams: Sendable {
    public let columnsCount: Int
    public let rowsCount: Int
    public let appsPerPage: Int
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let iconSize: CGFloat
    public let horizontalPadding: CGFloat
    public let topPadding: CGFloat

    public init(
        columnsCount: Int,
        rowsCount: Int,
        appsPerPage: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSize: CGFloat,
        horizontalPadding: CGFloat,
        topPadding: CGFloat
    ) {
        self.columnsCount = columnsCount
        self.rowsCount = rowsCount
        self.appsPerPage = appsPerPage
        self.cellWidth = cellWidth
        self.cellHeight = cellHeight
        self.iconSize = iconSize
        self.horizontalPadding = horizontalPadding
        self.topPadding = topPadding
    }
}
