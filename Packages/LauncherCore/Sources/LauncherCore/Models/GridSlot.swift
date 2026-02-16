//
//  GridSlot.swift
//  LauncherCore
//
//  A single slot in the grid containing position and content
//

import Foundation

public struct GridSlot: Equatable, Sendable {
    public let position: GridPosition
    public var content: SlotContent

    public init(position: GridPosition, content: SlotContent = .empty) {
        self.position = position
        self.content = content
    }

    public var isEmpty: Bool {
        content.isEmpty
    }

    public var isOccupied: Bool {
        !content.isEmpty
    }
}
