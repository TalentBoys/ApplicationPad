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
    private let mergeZoneRatio: CGFloat = 0.6            // 60% center area for merge
    private let velocityThreshold: CGFloat = 800        // pixels/second - fast = reorder

    // Internal state
    private var hoverTimer: Timer?
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
        appsPerPage: Int
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
            appsPerPage: appsPerPage
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
        appsPerPage: Int
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
        let targetIndex = currentPage * appsPerPage + targetIndexInPage

        // Check if there's an item at this position
        guard targetIndex >= 0, targetIndex < gridItems.count else {
            return .none
        }

        let targetItem = gridItems[targetIndex]

        // Don't target self
        guard targetItem.id != draggingItemId else {
            return .none
        }

        // Find dragging item and its current index
        guard let draggingIndex = gridItems.firstIndex(where: { $0.id == draggingItemId }) else {
            return .none
        }
        let draggingItem = gridItems[draggingIndex]

        // Calculate icon center position
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
            return .mergeZone(targetId: targetItem.id, targetIndex: targetIndex, isFolder: isFolder)
        }

        // For reorder: check if drag position has crossed the target's center
        // This ensures we only swap when the dragged item truly "passes" the target
        //
        // Key insight: after a reorder, the dragging item's index changes in the array,
        // but the user's intent is still based on their original drag direction.
        // We should trigger reorder when the drag position crosses the target center,
        // regardless of current indices (which change after each reorder).
        let shouldTriggerReorder: Bool

        // Simply check if we're past the center of the target cell
        // If dragging position is right of center, we want to be at or after this position
        // If dragging position is left of center, we want to be at or before this position
        if position.x > iconCenterX {
            // Position is right of target center - reorder if target is before us
            shouldTriggerReorder = draggingIndex < targetIndex
        } else {
            // Position is left of target center - reorder if target is after us
            shouldTriggerReorder = draggingIndex > targetIndex
        }

        if shouldTriggerReorder {
            // Cache reorder info for logging when triggered
            pendingReorderInfo = ReorderInfo(
                draggingName: draggingItem.name,
                draggingIndex: draggingIndex,
                draggingPosition: position,
                targetName: targetItem.name,
                targetIndex: targetIndex,
                targetCenter: targetCenter
            )
            return .reorderZone(targetIndex: targetIndex)
        }

        return .none
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
}
