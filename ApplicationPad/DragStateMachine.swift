//
//  DragStateMachine.swift
//  ApplicationPad
//
//  State machine for drag-to-merge vs drag-to-reorder behavior
//  Following macOS Launchpad philosophy: "Reorder is default, merge is intentional"
//

import Foundation
import SwiftUI
import Combine

// MARK: - Merge Display State (for UI updates only)

enum MergeDisplayState: Equatable {
    case none
    case hovering(targetId: UUID)
    case ready(targetId: UUID)

    var targetId: UUID? {
        switch self {
        case .none: return nil
        case .hovering(let id), .ready(let id): return id
        }
    }

    var isHovering: Bool {
        if case .hovering = self { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Drag State

enum DragState: Equatable {
    case idle
    case dragging
    case reorderCandidate(targetIndex: Int)
    case mergeHovering(targetId: UUID, startTime: Date)
    case mergeReady(targetId: UUID)

    var targetId: UUID? {
        switch self {
        case .mergeHovering(let id, _), .mergeReady(let id):
            return id
        default:
            return nil
        }
    }

    var isMergeHovering: Bool {
        if case .mergeHovering = self { return true }
        return false
    }

    var isMergeReady: Bool {
        if case .mergeReady = self { return true }
        return false
    }

    var isReorderCandidate: Bool {
        if case .reorderCandidate = self { return true }
        return false
    }
}

// MARK: - Drag Event

enum DragEvent {
    case startDrag
    case enterMergeZone(targetId: UUID)
    case enterReorderZone(targetIndex: Int)
    case leaveTarget
    case hoverTimerFired
    case highVelocityDetected
    case endDrag
}

// MARK: - Hit Zone

enum HitZone: Equatable {
    case none
    case mergeZone(targetId: UUID, targetIndex: Int, isFolder: Bool)
    case reorderZone(targetIndex: Int)
}

// MARK: - Reorder Info (for logging)

struct ReorderInfo {
    let draggingName: String
    let draggingIndex: Int
    let draggingPosition: CGPoint
    let targetName: String
    let targetIndex: Int
    let targetCenter: CGPoint
}

// MARK: - Drag State Machine

@MainActor
class DragStateMachine: ObservableObject {
    // Only publish merge-related states to minimize view updates
    @Published private(set) var mergeState: MergeDisplayState = .none

    // Internal state (not published)
    private var internalState: DragState = .idle

    var state: DragState { internalState }

    // Configuration
    private let mergeHoverDuration: TimeInterval = 0.35  // Time to confirm merge
    private let folderOpenDelay: TimeInterval = 2.0      // Time to open folder when dragging over it
    private let mergeZoneRatio: CGFloat = 1.0            // 100% icon area for merge
    private let velocityThreshold: CGFloat = 800        // pixels/second - fast = reorder

    // Internal state
    private var hoverTimer: Timer?
    private var folderOpenTimer: Timer?
    private var lastDragPosition: CGPoint = .zero
    private var lastDragTime: Date = .now
    private var currentVelocity: CGFloat = 0

    // Throttling
    private var lastHitZone: HitZone = .none
    private var lastUpdateTime: Date = .distantPast
    private let updateThrottleInterval: TimeInterval = 0.016 // ~60fps

    // Reorder info cache (for logging)
    private var pendingReorderInfo: ReorderInfo?

    // Callbacks
    var onReorder: ((Int) -> Void)?
    var onMergeReady: ((UUID) -> Void)?
    var onFolderOpen: ((UUID) -> Void)?  // Called when folder should open during drag

    // MARK: - Public API

    func startDrag() {
        transition(with: .startDrag)
        lastDragPosition = .zero
        lastDragTime = .now
        currentVelocity = 0
        lastHitZone = .none
        lastUpdateTime = .distantPast
    }

    func updateDrag(
        position: CGPoint,
        gridItems: [LauncherItem],
        draggingItemId: UUID,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSize: CGFloat,
        columnsCount: Int,
        rowsCount: Int,
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        currentPage: Int,
        appsPerPage: Int,
        dragFromIndex: Int? = nil,  // Original index of dragging item
        dragToIndex: Int? = nil     // Current visual target index
    ) {
        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval else {
            return
        }
        lastUpdateTime = now

        // Calculate velocity
        let timeDelta = now.timeIntervalSince(lastDragTime)
        if timeDelta > 0.01 {
            let distance = hypot(position.x - lastDragPosition.x, position.y - lastDragPosition.y)
            currentVelocity = distance / timeDelta
        }
        lastDragPosition = position
        lastDragTime = now

        // Determine hit zone
        let hitZone = calculateHitZone(
            position: position,
            gridItems: gridItems,
            draggingItemId: draggingItemId,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            iconSize: iconSize,
            columnsCount: columnsCount,
            rowsCount: rowsCount,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding,
            currentPage: currentPage,
            appsPerPage: appsPerPage,
            dragFromIndex: dragFromIndex,
            dragToIndex: dragToIndex
        )

        // Skip if hit zone hasn't changed (for non-velocity-based transitions)
        if hitZone == lastHitZone && currentVelocity < velocityThreshold {
            return
        }
        lastHitZone = hitZone

        // Process hit zone
        processHitZone(hitZone)
    }

    func endDrag() -> (shouldMerge: Bool, targetId: UUID?) {
        let result: (shouldMerge: Bool, targetId: UUID?)

        print("🛑 endDrag called, current state=\(internalState)")

        switch internalState {
        case .mergeReady(let targetId):
            print("   ✅ State is mergeReady, will merge with \(targetId.uuidString.prefix(8))")
            result = (true, targetId)
        case .mergeHovering(let targetId, let startTime):
            // Check if user has been hovering long enough (at least half the required time)
            // This allows merge even if user releases slightly before timer fires
            let elapsedTime = Date().timeIntervalSince(startTime)
            let minimumHoverTime = mergeHoverDuration * 0.5  // 50% of required time
            if elapsedTime >= minimumHoverTime {
                print("   ✅ State is mergeHovering but elapsed time \(String(format: "%.2f", elapsedTime))s >= \(String(format: "%.2f", minimumHoverTime))s, will merge with \(targetId.uuidString.prefix(8))")
                result = (true, targetId)
            } else {
                print("   ❌ State is mergeHovering but elapsed time \(String(format: "%.2f", elapsedTime))s < \(String(format: "%.2f", minimumHoverTime))s, not long enough")
                result = (false, nil)
            }
        default:
            print("   ❌ State is NOT mergeReady")
            result = (false, nil)
        }

        transition(with: .endDrag)
        cancelHoverTimer()
        return result
    }

    func reset() {
        internalState = .idle
        mergeState = .none
        cancelHoverTimer()
        cancelFolderOpenTimer()
        currentVelocity = 0
        lastHitZone = .none
    }

    // MARK: - Hit Zone Calculation

    private func calculateHitZone(
        position: CGPoint,
        gridItems: [LauncherItem],
        draggingItemId: UUID,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        iconSize: CGFloat,
        columnsCount: Int,
        rowsCount: Int,
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        currentPage: Int,
        appsPerPage: Int,
        dragFromIndex: Int? = nil,
        dragToIndex: Int? = nil
    ) -> HitZone {
        // Clear pending reorder info
        pendingReorderInfo = nil

        // Calculate which cell we're over using floor for consistent behavior
        let col = Int(floor((position.x - horizontalPadding) / cellWidth))
        let row = Int(floor((position.y - topPadding) / cellHeight))

        // Bounds check
        guard col >= 0, col < columnsCount, row >= 0, row < rowsCount else {
            return .none
        }

        let targetIndexInPage = row * columnsCount + col
        let visualTargetIndex = currentPage * appsPerPage + targetIndexInPage

        // Map visual position to actual array index, accounting for ongoing reorder
        // If we're in the middle of a reorder (dragFromIndex != dragToIndex),
        // the visual positions are different from array positions
        let actualTargetIndex: Int
        if let fromIndex = dragFromIndex, let toIndex = dragToIndex, fromIndex != toIndex {
            // Map visual index back to array index
            actualTargetIndex = mapVisualToArrayIndex(visualIndex: visualTargetIndex, fromIndex: fromIndex, toIndex: toIndex, totalItems: gridItems.count)
        } else {
            actualTargetIndex = visualTargetIndex
        }

        // Check if there's an item at this position
        guard actualTargetIndex >= 0, actualTargetIndex < gridItems.count else {
            return .none
        }

        let targetItem = gridItems[actualTargetIndex]

        // Skip empty slots - they can't be merge targets
        guard !targetItem.isEmpty else {
            return .none
        }

        // Don't target self
        guard targetItem.id != draggingItemId else {
            return .none
        }

        // Find dragging item and its current index
        guard let draggingIndex = gridItems.firstIndex(where: { $0.id == draggingItemId }) else {
            return .none
        }
        let draggingItem = gridItems[draggingIndex]

        // Calculate icon center position (using visual position)
        let iconCenterX = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
        let iconCenterY = topPadding + cellHeight * (CGFloat(row) + 0.5)
        let targetCenter = CGPoint(x: iconCenterX, y: iconCenterY)

        // Calculate distance from icon center
        let dx = position.x - iconCenterX
        let dy = position.y - iconCenterY
        let distanceFromCenter = hypot(dx, dy)

        // Use circular zones for symmetric hit detection
        let mergeRadius = iconSize * mergeZoneRatio / 2

        if distanceFromCenter <= mergeRadius {
            // Check if target is a folder
            let isFolder: Bool
            if case .folder = targetItem {
                isFolder = true
            } else {
                isFolder = false
            }
            return .mergeZone(targetId: targetItem.id, targetIndex: actualTargetIndex, isFolder: isFolder)
        }

        // For reorder: check if drag position has fully exited the target cell
        // This ensures reorder only triggers when truly moving past the target
        //
        // Key insight: reorder should only happen when the drag position is
        // clearly outside the target's icon area, not just past the center.
        let shouldTriggerReorder: Bool

        // Check if we're outside the icon area (using cell boundaries for clearer separation)
        let iconLeft = iconCenterX - iconSize / 2
        let iconRight = iconCenterX + iconSize / 2
        let iconTop = iconCenterY - iconSize / 2
        let iconBottom = iconCenterY + iconSize / 2

        // Determine if position is clearly outside the icon bounds
        let isOutsideHorizontally = position.x < iconLeft || position.x > iconRight
        let isOutsideVertically = position.y < iconTop || position.y > iconBottom

        // Only trigger reorder if we're outside the icon area
        if isOutsideHorizontally || isOutsideVertically {
            // Check direction: should we swap with this target?
            if position.x > iconRight {
                // Position is right of target - reorder if target is before us
                shouldTriggerReorder = draggingIndex < visualTargetIndex
            } else if position.x < iconLeft {
                // Position is left of target - reorder if target is after us
                shouldTriggerReorder = draggingIndex > visualTargetIndex
            } else if position.y > iconBottom {
                // Position is below target (but within horizontal bounds)
                // For same row movement, this means we're moving to next row
                shouldTriggerReorder = draggingIndex < visualTargetIndex
            } else if position.y < iconTop {
                // Position is above target (but within horizontal bounds)
                // For same row movement, this means we're moving to previous row
                shouldTriggerReorder = draggingIndex > visualTargetIndex
            } else {
                shouldTriggerReorder = false
            }
        } else {
            shouldTriggerReorder = false
        }

        if shouldTriggerReorder {
            // Cache reorder info for logging when triggered
            pendingReorderInfo = ReorderInfo(
                draggingName: draggingItem.name,
                draggingIndex: draggingIndex,
                draggingPosition: position,
                targetName: targetItem.name,
                targetIndex: actualTargetIndex,
                targetCenter: targetCenter
            )
            return .reorderZone(targetIndex: visualTargetIndex)  // Return visual index for reorder
        }

        return .none
    }

    // Helper function to map visual position to actual array index during drag
    private func mapVisualToArrayIndex(visualIndex: Int, fromIndex: Int, toIndex: Int, totalItems: Int) -> Int {
        // If visual position equals the target position, it shows the dragging item
        if visualIndex == toIndex {
            return fromIndex  // The dragging item is at fromIndex in the array
        }

        // For other positions, we need to reverse the visual shift
        if fromIndex < toIndex {
            // Dragging right: items between from+1..to have shifted left visually
            // So visual position X corresponds to array position X+1 in that range
            if visualIndex >= fromIndex && visualIndex < toIndex {
                return visualIndex + 1
            }
        } else {
            // Dragging left: items between to+1..from have shifted right visually
            // So visual position X corresponds to array position X-1 in that range
            if visualIndex > toIndex && visualIndex <= fromIndex {
                return visualIndex - 1
            }
        }

        // Outside the affected range, visual = actual
        return visualIndex
    }

    // MARK: - Process Hit Zone

    private func processHitZone(_ hitZone: HitZone) {
        print("🎯 processHitZone: \(hitZone), velocity=\(String(format: "%.1f", currentVelocity)), state=\(state)")

        // High velocity always triggers reorder
        if currentVelocity > velocityThreshold {
            print("   ⚡ High velocity detected, forcing reorder")
            transition(with: .highVelocityDetected)

            switch hitZone {
            case .mergeZone(_, let index, _), .reorderZone(let index):
                transition(with: .enterReorderZone(targetIndex: index))
            case .none:
                transition(with: .leaveTarget)
            }
            return
        }

        switch hitZone {
        case .none:
            transition(with: .leaveTarget)
            cancelFolderOpenTimer()  // Cancel folder timer when leaving target

        case .mergeZone(let targetId, _, let isFolder):
            print("   📍 In merge zone for target \(targetId.uuidString.prefix(8)), isFolder=\(isFolder)")

            // If target is a folder, immediately go to mergeReady (no hover delay needed)
            if isFolder {
                print("   📁 Target is folder, immediately ready to merge")
                // Skip hovering state, go directly to mergeReady
                if case .mergeReady(let currentTargetId) = state, currentTargetId == targetId {
                    // Already ready for this target
                    return
                }
                cancelHoverTimer()
                internalState = .mergeReady(targetId: targetId)
                updateMergeDisplayState()
                onMergeReady?(targetId)

                // Start folder open timer (2s delay to open folder)
                startFolderOpenTimer(targetId: targetId)
                return
            }

            // For app targets, use hover delay
            // Check if we're already hovering over this target
            if case .mergeHovering(let currentTargetId, _) = state, currentTargetId == targetId {
                // Continue hovering, timer will handle transition to mergeReady
                print("   ⏳ Already hovering, waiting for timer...")
                return
            }
            print("   🆕 Starting hover on new target")
            cancelFolderOpenTimer()  // Cancel folder timer when not hovering over folder
            transition(with: .enterMergeZone(targetId: targetId))
            startHoverTimer()

        case .reorderZone(let targetIndex):
            transition(with: .enterReorderZone(targetIndex: targetIndex))
        }
    }

    // MARK: - State Transitions

    private func transition(with event: DragEvent) {
        let newState = nextState(for: event)
        if newState != internalState {
            print("🔄 State transition: \(internalState) --[\(event)]--> \(newState)")
            internalState = newState
            updateMergeDisplayState()
        }
    }

    private func updateMergeDisplayState() {
        let newMergeState: MergeDisplayState
        switch internalState {
        case .mergeHovering(let targetId, _):
            newMergeState = .hovering(targetId: targetId)
        case .mergeReady(let targetId):
            newMergeState = .ready(targetId: targetId)
        default:
            newMergeState = .none
        }

        // Only update @Published if actually changed
        if newMergeState != mergeState {
            mergeState = newMergeState
        }
    }

    private func triggerReorder(_ index: Int) {
        if let info = pendingReorderInfo {
            print("🔄 Reorder: [\(info.draggingName)][\(info.draggingIndex)] at (\(String(format: "%.1f", info.draggingPosition.x)), \(String(format: "%.1f", info.draggingPosition.y))) → [\(info.targetName)][\(info.targetIndex)] at (\(String(format: "%.1f", info.targetCenter.x)), \(String(format: "%.1f", info.targetCenter.y))) => newIndex=\(index)")
        }
        onReorder?(index)
    }

    private func nextState(for event: DragEvent) -> DragState {
        switch (state, event) {
        // From idle
        case (.idle, .startDrag):
            return .dragging

        // From dragging
        case (.dragging, .enterMergeZone(let targetId)):
            return .mergeHovering(targetId: targetId, startTime: Date())
        case (.dragging, .enterReorderZone(let index)):
            triggerReorder(index)
            return .reorderCandidate(targetIndex: index)
        case (.dragging, .endDrag):
            return .idle

        // From reorderCandidate
        case (.reorderCandidate, .enterMergeZone(let targetId)):
            return .mergeHovering(targetId: targetId, startTime: Date())
        case (.reorderCandidate, .enterReorderZone(let index)):
            triggerReorder(index)
            return .reorderCandidate(targetIndex: index)
        case (.reorderCandidate, .leaveTarget):
            return .dragging
        case (.reorderCandidate, .endDrag):
            return .idle

        // From mergeHovering
        case (.mergeHovering(let targetId, _), .hoverTimerFired):
            onMergeReady?(targetId)
            return .mergeReady(targetId: targetId)
        case (.mergeHovering, .enterReorderZone(let index)):
            cancelHoverTimer()
            triggerReorder(index)
            return .reorderCandidate(targetIndex: index)
        case (.mergeHovering, .leaveTarget):
            cancelHoverTimer()
            return .dragging
        case (.mergeHovering, .highVelocityDetected):
            cancelHoverTimer()
            return .dragging
        case (.mergeHovering(_, let startTime), .enterMergeZone(let newTargetId)):
            // Switching to a different target
            cancelHoverTimer()
            return .mergeHovering(targetId: newTargetId, startTime: startTime)
        case (.mergeHovering, .endDrag):
            cancelHoverTimer()
            return .idle

        // From mergeReady
        case (.mergeReady, .leaveTarget):
            return .dragging
        case (.mergeReady, .enterReorderZone(let index)):
            triggerReorder(index)
            return .reorderCandidate(targetIndex: index)
        case (.mergeReady, .highVelocityDetected):
            return .dragging
        case (.mergeReady, .endDrag):
            return .idle

        // Default - stay in current state
        default:
            return state
        }
    }

    // MARK: - Hover Timer

    private func startHoverTimer() {
        cancelHoverTimer()
        print("⏱️ Starting hover timer for \(mergeHoverDuration)s")
        hoverTimer = Timer.scheduledTimer(withTimeInterval: mergeHoverDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                print("⏱️ Hover timer fired!")
                self?.transition(with: .hoverTimerFired)
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    // MARK: - Folder Open Timer

    private func startFolderOpenTimer(targetId: UUID) {
        cancelFolderOpenTimer()
        print("📂 Starting folder open timer for \(folderOpenDelay)s")
        folderOpenTimer = Timer.scheduledTimer(withTimeInterval: folderOpenDelay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                print("📂 Folder open timer fired!")
                self?.onFolderOpen?(targetId)
            }
        }
    }

    private func cancelFolderOpenTimer() {
        folderOpenTimer?.invalidate()
        folderOpenTimer = nil
    }
}
