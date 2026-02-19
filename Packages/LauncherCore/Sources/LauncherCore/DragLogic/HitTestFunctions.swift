//
//  HitTestFunctions.swift
//  LauncherCore
//
//  Pure functions for hit testing during drag operations
//

import Foundation

// MARK: - Function 1: Calculate Hit Position (位置判定函数)

/// Determines the current position of the cursor in the grid
/// - Parameters:
///   - position: The cursor position (x, y)
///   - currentPage: The currently displayed page
///   - layout: Grid layout parameters
/// - Returns: HitPositionResult containing page, cell coordinate, and region
public func calculateHitPosition(
    position: CGPoint,
    currentPage: Int,
    layout: GridLayoutParams
) -> HitPositionResult {
    // Calculate which cell we're over using floor for consistent behavior
    let col = Int(floor((position.x - layout.horizontalPadding) / layout.cellWidth))
    let row = Int(floor((position.y - layout.topPadding) / layout.cellHeight))

    // Bounds check - if outside grid, return not in cell
    guard col >= 0, col < layout.columnsCount, row >= 0, row < layout.rowsCount else {
        return .notInCell(page: currentPage)
    }

    let cell = CellCoordinate(page: currentPage, row: row, column: col)

    // Calculate cell center position
    let cellCenterX = layout.horizontalPadding + layout.cellWidth * (CGFloat(col) + 0.5)
    let cellCenterY = layout.topPadding + layout.cellHeight * (CGFloat(row) + 0.5)

    // Calculate relative position from cell center
    let relativeX = position.x - cellCenterX
    let relativeY = position.y - cellCenterY

    // Determine region based on icon size
    let halfIconSize = layout.iconSize / 2
    let region = determineRegion(relativeX: relativeX, relativeY: relativeY, halfIconSize: halfIconSize)

    return HitPositionResult(page: currentPage, cell: cell, region: region)
}

/// Helper: Determine which region of the cell the cursor is in
private func determineRegion(relativeX: CGFloat, relativeY: CGFloat, halfIconSize: CGFloat) -> CellRegion {
    // Check if inside icon area (center)
    if abs(relativeX) <= halfIconSize && abs(relativeY) <= halfIconSize {
        return .center
    }

    // Determine horizontal position: left, center, right
    let horizontalPosition: Int // -1 = left, 0 = center, 1 = right
    if relativeX < -halfIconSize {
        horizontalPosition = -1
    } else if relativeX > halfIconSize {
        horizontalPosition = 1
    } else {
        horizontalPosition = 0
    }

    // Determine vertical position: top, center, bottom
    let verticalPosition: Int // -1 = top, 0 = center, 1 = bottom
    if relativeY < -halfIconSize {
        verticalPosition = -1
    } else if relativeY > halfIconSize {
        verticalPosition = 1
    } else {
        verticalPosition = 0
    }

    // Map to CellRegion
    switch (horizontalPosition, verticalPosition) {
    case (-1, -1): return .topLeft
    case (0, -1):  return .topCenter
    case (1, -1):  return .topRight
    case (-1, 0):  return .centerLeft
    case (0, 0):   return .center  // Should not reach here due to early return
    case (1, 0):   return .centerRight
    case (-1, 1):  return .bottomLeft
    case (0, 1):   return .bottomCenter
    case (1, 1):   return .bottomRight
    default:       return .center  // Fallback
    }
}

// MARK: - Function 2: Determine Operation (操作判定函数)

/// Determines what operation to perform based on hit position
/// - Parameters:
///   - hitResult: The result from calculateHitPosition
///   - items: Current grid items (to check if cell is empty)
///   - draggingItemId: The ID of the item being dragged (to exclude self)
///   - layout: Grid layout parameters
/// - Returns: The operation to perform
public func determineOperation(
    hitResult: HitPositionResult,
    items: [LauncherItem],
    draggingItemId: UUID,
    layout: GridLayoutParams
) -> DragOperation {
    // If not in any cell, no operation
    guard let cell = hitResult.cell, let region = hitResult.region else {
        return .none
    }

    // Get the index of this cell
    let index = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)

    // If index is out of bounds, treat as empty (can place)
    guard index < items.count else {
        return .placeInEmpty
    }

    let targetItem = items[index]

    // Don't operate on self
    if targetItem.id == draggingItemId {
        return .none
    }

    // If cell is empty, place in empty
    if targetItem.isEmpty {
        return .placeInEmpty
    }

    // Cell has an app or folder, determine operation based on region
    switch region {
    case .topLeft, .bottomLeft, .centerLeft:
        return .insertLeft

    case .topRight, .bottomRight, .centerRight:
        return .insertRight

    case .topCenter:
        return .insertAbove

    case .bottomCenter:
        return .insertBelow

    case .center:
        return .merge
    }
}

// MARK: - Function 3: Apply Operation (状态操作函数)

/// Extension on GridState to apply drag operations
extension GridState {

    /// Apply a drag operation to the grid state
    /// IMPORTANT: Each call recalculates preview from stable, not from previous preview
    /// - Parameters:
    ///   - operation: The operation to perform
    ///   - targetCell: The target cell coordinate
    ///   - sourceIndex: The index of the item being dragged (in stable)
    ///   - layout: Grid layout parameters
    /// - Returns: The new index of the dragged item (for tracking), or nil if cancelled
    @discardableResult
    public func applyOperation(
        operation: DragOperation,
        targetCell: CellCoordinate?,
        sourceIndex: Int,
        layout: GridLayoutParams
    ) -> Int? {
        switch operation {
        case .none:
            // Cancel preview, revert to stable
            cancelPreview()
            return nil

        case .placeInEmpty:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            return applyPlaceInEmpty(sourceIndex: sourceIndex, targetIndex: targetIndex)

        case .insertLeft:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            let isRowStart = cell.column == 0

            if sourceIndex < targetIndex {
                // Source before target: prefer squeeze left (use the empty slot left by source)
                if isRowStart {
                    // Row-start: target shifts forward, insert at targetIndex
                    return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex + 1, preferSqueezeLeft: true, layout: layout)
                } else {
                    // Not row-start: target stays, items before target shift left
                    return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex, preferSqueezeLeft: true, layout: layout)
                }
            } else {
                // Source after target: prefer squeeze right (use the empty slot left by source)
                return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex, preferSqueezeLeft: false, layout: layout)
            }

        case .insertRight:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            let isRowEnd = cell.column == layout.columnsCount - 1

            // insertRight means: place source to the RIGHT of target
            // We need to find space WITHOUT moving the target itself
            //
            // Key insight: We should look for empty slot AFTER targetIndex first,
            // because that's where we want to insert. Only if no empty after,
            // then we shift items LEFT (including target) to make room.
            if isRowEnd {
                // Row-end special case: prefer squeeze left since there's no visual "right"
                if sourceIndex < targetIndex {
                    return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex + 1, preferSqueezeLeft: true, layout: layout)
                } else {
                    return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex, preferSqueezeLeft: false, layout: layout)
                }
            } else {
                // Normal case: prefer squeeze right to keep target in place
                // Only squeeze left if absolutely necessary (no empty after targetIndex+1)
                return applyInsertAt(sourceIndex: sourceIndex, targetIndex: targetIndex + 1, preferSqueezeLeft: false, layout: layout)
            }

        case .insertAbove:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            let insertIndex = targetIndex - layout.columnsCount
            if insertIndex >= 0 {
                return applyInsertAt(sourceIndex: sourceIndex, targetIndex: insertIndex, preferSqueezeLeft: false, layout: layout)
            } else {
                // Above first row - insert at beginning of page
                return applyInsertAt(sourceIndex: sourceIndex, targetIndex: cell.page * layout.appsPerPage, preferSqueezeLeft: false, layout: layout)
            }

        case .insertBelow:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            let insertIndex = targetIndex + layout.columnsCount
            return applyInsertAt(sourceIndex: sourceIndex, targetIndex: insertIndex, preferSqueezeLeft: false, layout: layout)

        case .merge:
            guard let cell = targetCell else {
                cancelPreview()
                return nil
            }
            let targetIndex = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            return applyMerge(sourceIndex: sourceIndex, targetIndex: targetIndex)
        }
    }

    // MARK: - Private Helper Methods

    /// Place item into an empty cell (swap)
    /// Always recalculates from stable state (sourceIndex is the original position in stable)
    private func applyPlaceInEmpty(sourceIndex: Int, targetIndex: Int) -> Int? {
        // Always start from stable - each operation recalculates from stable
        var newPreview = stableItems
        guard sourceIndex >= 0 && sourceIndex < newPreview.count else { return nil }
        guard targetIndex >= 0 else { return nil }

        // If target is beyond array, expand with empty slots
        while targetIndex >= newPreview.count {
            newPreview.append(.empty(UUID()))
        }

        // Swap source and target
        let sourceItem = newPreview[sourceIndex]
        newPreview[sourceIndex] = .empty(UUID())
        newPreview[targetIndex] = sourceItem

        setPreviewItems(newPreview)
        return targetIndex
    }

    /// Insert at position with cascading shift
    /// Always recalculates from stable state (sourceIndex is the original position in stable)
    /// - Parameters:
    ///   - sourceIndex: Original position in stable
    ///   - targetIndex: Position to insert at
    ///   - preferSqueezeLeft: If true, prefer shifting items left (used for insertRight to row-end)
    ///   - layout: Grid layout parameters
    /// - Returns: Final index where item was placed
    private func applyInsertAt(sourceIndex: Int, targetIndex: Int, preferSqueezeLeft: Bool, layout: GridLayoutParams) -> Int? {
        // Always start from stable - each operation recalculates from stable
        var newPreview = stableItems
        guard sourceIndex >= 0 && sourceIndex < newPreview.count else { return nil }

        let sourceItem = newPreview[sourceIndex]

        // Step 1: Mark source as empty
        newPreview[sourceIndex] = .empty(UUID())

        // Calculate page boundaries - IMPORTANT: limit search to current page only
        // to prevent pushing items to next page when current page has space
        let sourcePage = sourceIndex / layout.appsPerPage
        let clampedTargetIndex = min(targetIndex, newPreview.count - 1)
        let targetPage = clampedTargetIndex / layout.appsPerPage
        let currentPage = max(sourcePage, targetPage)
        let pageStart = currentPage * layout.appsPerPage
        let pageEnd = min((currentPage + 1) * layout.appsPerPage, newPreview.count)

        // Clamp targetIndex to valid range for this page
        let searchStartAfter = min(targetIndex, pageEnd)
        let searchStartBefore = min(targetIndex - 1, pageEnd - 1)

        // Step 2: Find empty slots in both directions (within current page)
        var emptySlotAfter: Int? = nil
        if searchStartAfter < pageEnd {
            for i in searchStartAfter..<pageEnd {
                if newPreview[i].isEmpty {
                    emptySlotAfter = i
                    break
                }
            }
        }

        var emptySlotBefore: Int? = nil
        if searchStartBefore >= pageStart {
            for i in stride(from: searchStartBefore, through: pageStart, by: -1) {
                if newPreview[i].isEmpty {
                    emptySlotBefore = i
                    break
                }
            }
        }

        // Step 3: Apply the appropriate shift based on preference and availability
        var finalTargetIndex: Int

        if preferSqueezeLeft {
            // Prefer squeezing left first (for insertRight to row-end)
            if let emptyBefore = emptySlotBefore {
                // Shift left: move items from emptySlotBefore forward to targetIndex - 1
                var currentIndex = emptyBefore
                while currentIndex < targetIndex - 1 {
                    newPreview[currentIndex] = newPreview[currentIndex + 1]
                    currentIndex += 1
                }
                // Item goes at targetIndex - 1 (since we shifted left)
                finalTargetIndex = targetIndex - 1
            } else if let emptyAfter = emptySlotAfter {
                // Fallback: shift right
                var currentIndex = emptyAfter
                while currentIndex > targetIndex && currentIndex > 0 {
                    newPreview[currentIndex] = newPreview[currentIndex - 1]
                    currentIndex -= 1
                }
                finalTargetIndex = targetIndex
            } else {
                // No empty slot found anywhere, need to add one and shift right
                newPreview.append(.empty(UUID()))
                var currentIndex = newPreview.count - 1
                while currentIndex > targetIndex && currentIndex > 0 {
                    newPreview[currentIndex] = newPreview[currentIndex - 1]
                    currentIndex -= 1
                }
                finalTargetIndex = targetIndex
            }
        } else {
            // Default: prefer squeezing right first
            if let emptyAfter = emptySlotAfter {
                // Shift right: move items from emptySlotAfter back to targetIndex
                var currentIndex = emptyAfter
                while currentIndex > targetIndex && currentIndex > 0 {
                    newPreview[currentIndex] = newPreview[currentIndex - 1]
                    currentIndex -= 1
                }
                finalTargetIndex = targetIndex
            } else if let emptyBefore = emptySlotBefore {
                // Fallback: shift left
                var currentIndex = emptyBefore
                while currentIndex < targetIndex - 1 {
                    newPreview[currentIndex] = newPreview[currentIndex + 1]
                    currentIndex += 1
                }
                // Item goes at targetIndex - 1 (since we shifted left)
                finalTargetIndex = targetIndex - 1
            } else {
                // No empty slot found anywhere, need to add one and shift right
                newPreview.append(.empty(UUID()))
                var currentIndex = newPreview.count - 1
                while currentIndex > targetIndex && currentIndex > 0 {
                    newPreview[currentIndex] = newPreview[currentIndex - 1]
                    currentIndex -= 1
                }
                finalTargetIndex = targetIndex
            }
        }

        // Step 4: Place the source item at final target
        finalTargetIndex = min(finalTargetIndex, newPreview.count - 1)
        finalTargetIndex = max(finalTargetIndex, 0)
        newPreview[finalTargetIndex] = sourceItem

        setPreviewItems(newPreview)

        // Return the actual index where item was placed
        return finalTargetIndex
    }

    /// Merge items (create folder or add to folder)
    /// Always recalculates from stable state (sourceIndex is the original position in stable)
    private func applyMerge(sourceIndex: Int, targetIndex: Int) -> Int? {
        // Always start from stable - each operation recalculates from stable
        var newPreview = stableItems
        guard sourceIndex >= 0 && sourceIndex < newPreview.count else { return nil }
        guard targetIndex >= 0 && targetIndex < newPreview.count else { return nil }
        guard sourceIndex != targetIndex else { return nil }

        let sourceItem = newPreview[sourceIndex]
        let targetItem = newPreview[targetIndex]

        // Get apps from source
        var appsToAdd: [AppItem] = []
        switch sourceItem {
        case .app(let app):
            appsToAdd.append(app)
        case .folder(let folder):
            appsToAdd.append(contentsOf: folder.apps)
        case .empty:
            return nil
        }

        // Merge into target
        let newItem: LauncherItem
        switch targetItem {
        case .folder(var folder):
            folder.slots.append(contentsOf: appsToAdd.map { .app($0) })
            newItem = .folder(folder)
        case .app(let app):
            var apps = [app]
            apps.append(contentsOf: appsToAdd)
            newItem = .folder(FolderItem(name: "Folder", apps: apps))
        case .empty:
            return nil
        }

        // Update items
        newPreview[sourceIndex] = .empty(UUID())
        newPreview[targetIndex] = newItem

        setPreviewItems(newPreview)
        return targetIndex
    }
}
