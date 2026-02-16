//
//  DropIntent.swift
//  LauncherCore
//
//  Describes the intended drop action during drag operations
//

import Foundation

public enum DropIntent: Equatable, Sendable {
    /// Drop into an empty slot
    case intoEmpty(position: GridPosition)

    /// Insert before the target, pushing it and subsequent items forward
    case insertBefore(target: GridPosition)

    /// Insert after the target, pushing subsequent items forward
    case insertAfter(target: GridPosition)

    /// Merge with target to create/add to folder
    case merge(target: GridPosition)

    public var targetPosition: GridPosition {
        switch self {
        case .intoEmpty(let position): return position
        case .insertBefore(let target): return target
        case .insertAfter(let target): return target
        case .merge(let target): return target
        }
    }

    public var isMerge: Bool {
        if case .merge = self { return true }
        return false
    }

    public var isInsert: Bool {
        switch self {
        case .insertBefore, .insertAfter: return true
        default: return false
        }
    }
}
