//
//  GridPosition.swift
//  LauncherCore
//
//  Grid position representing row and column coordinates
//

import Foundation

public struct GridPosition: Hashable, Codable, Sendable {
    public let row: Int
    public let column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// Convert to linear index (row-major order)
    public func toLinearIndex(columns: Int) -> Int {
        row * columns + column
    }

    /// Create from linear index (row-major order)
    public static func fromLinearIndex(_ index: Int, columns: Int) -> GridPosition {
        GridPosition(row: index / columns, column: index % columns)
    }
}
