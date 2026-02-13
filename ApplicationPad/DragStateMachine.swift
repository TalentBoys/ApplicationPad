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
    case mergeZone(targetId: UUID, targetIndex: Int)
    case reorderZone(targetIndex: Int)
    case betweenIcons(insertIndex: Int)
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

        switch internalState {
        case .mergeReady(let targetId):
            result = (true, targetId)
        default:
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
        // Calculate which cell we're over
        let col = Int((position.x - horizontalPadding) / cellWidth)
        let row = Int((position.y - topPadding) / cellHeight)

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

        // Calculate icon center position
        let iconCenterX = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
        let iconCenterY = topPadding + cellHeight * (CGFloat(row) + 0.5)

        // Calculate distance from icon center
        let dx = position.x - iconCenterX
        let dy = position.y - iconCenterY

        // Merge zone is center 60% of icon
        let mergeZoneSize = iconSize * mergeZoneRatio
        let halfMergeZone = mergeZoneSize / 2

        // Check if in merge zone (center rectangle)
        let inMergeZone = abs(dx) <= halfMergeZone && abs(dy) <= halfMergeZone

        // Check if in icon area at all (for reorder zone)
        let halfIcon = iconSize / 2
        let inIconArea = abs(dx) <= halfIcon && abs(dy) <= halfIcon

        if inMergeZone {
            return .mergeZone(targetId: targetItem.id, targetIndex: targetIndex)
        } else if inIconArea {
            // In edge zone (reorder zone)
            return .reorderZone(targetIndex: targetIndex)
        } else {
            // Between icons - determine insertion point
            return .betweenIcons(insertIndex: targetIndex)
        }
    }

    // MARK: - Process Hit Zone

    private func processHitZone(_ hitZone: HitZone) {
        // High velocity always triggers reorder
        if currentVelocity > velocityThreshold {
            transition(with: .highVelocityDetected)

            switch hitZone {
            case .mergeZone(_, let index), .reorderZone(let index), .betweenIcons(let index):
                transition(with: .enterReorderZone(targetIndex: index))
            case .none:
                transition(with: .leaveTarget)
            }
            return
        }

        switch hitZone {
        case .none:
            transition(with: .leaveTarget)

        case .mergeZone(let targetId, _):
            // Check if we're already hovering over this target
            if case .mergeHovering(let currentTargetId, _) = state, currentTargetId == targetId {
                // Continue hovering, timer will handle transition to mergeReady
                return
            }
            transition(with: .enterMergeZone(targetId: targetId))
            startHoverTimer()

        case .reorderZone(let targetIndex):
            transition(with: .enterReorderZone(targetIndex: targetIndex))

        case .betweenIcons(let insertIndex):
            transition(with: .enterReorderZone(targetIndex: insertIndex))
        }
    }

    // MARK: - State Transitions

    private func transition(with event: DragEvent) {
        let newState = nextState(for: event)
        if newState != internalState {
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

    private func nextState(for event: DragEvent) -> DragState {
        switch (state, event) {
        // From idle
        case (.idle, .startDrag):
            return .dragging

        // From dragging
        case (.dragging, .enterMergeZone(let targetId)):
            return .mergeHovering(targetId: targetId, startTime: Date())
        case (.dragging, .enterReorderZone(let index)):
            onReorder?(index)
            return .reorderCandidate(targetIndex: index)
        case (.dragging, .endDrag):
            return .idle

        // From reorderCandidate
        case (.reorderCandidate, .enterMergeZone(let targetId)):
            return .mergeHovering(targetId: targetId, startTime: Date())
        case (.reorderCandidate, .enterReorderZone(let index)):
            onReorder?(index)
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
            onReorder?(index)
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
            onReorder?(index)
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
        hoverTimer = Timer.scheduledTimer(withTimeInterval: mergeHoverDuration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.transition(with: .hoverTimerFired)
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
