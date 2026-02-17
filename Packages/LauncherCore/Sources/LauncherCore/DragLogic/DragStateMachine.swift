//
//  DragStateMachine.swift
//  LauncherCore
//
//  State machine for drag-to-merge vs drag-to-reorder behavior
//  Following macOS Launchpad philosophy: "Reorder is default, merge is intentional"
//

import Foundation
import SwiftUI
import Combine

// MARK: - Merge Display State (for UI updates only)

public enum MergeDisplayState: Equatable, Sendable {
    case none
    case hovering(targetId: UUID)
    case ready(targetId: UUID)

    public var targetId: UUID? {
        switch self {
        case .none: return nil
        case .hovering(let id), .ready(let id): return id
        }
    }

    public var isHovering: Bool {
        if case .hovering = self { return true }
        return false
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Drag State

public enum DragState: Equatable, Sendable {
    case idle
    case dragging
    case reorderCandidate(operation: DragOperation, targetCell: CellCoordinate)
    case mergeHovering(targetId: UUID, targetCell: CellCoordinate, startTime: Date)
    case mergeReady(targetId: UUID, targetCell: CellCoordinate)

    public var targetId: UUID? {
        switch self {
        case .mergeHovering(let id, _, _), .mergeReady(let id, _):
            return id
        default:
            return nil
        }
    }

    public var isMergeHovering: Bool {
        if case .mergeHovering = self { return true }
        return false
    }

    public var isMergeReady: Bool {
        if case .mergeReady = self { return true }
        return false
    }

    public var isReorderCandidate: Bool {
        if case .reorderCandidate = self { return true }
        return false
    }
}

// MARK: - Drag Event

public enum DragEvent: Sendable {
    case startDrag
    case operationChanged(operation: DragOperation, targetCell: CellCoordinate?, targetId: UUID?, isFolder: Bool)
    case hoverTimerFired
    case highVelocityDetected
    case endDrag
}

// MARK: - Drag State Machine

@MainActor
public class DragStateMachine: ObservableObject {
    // Only publish merge-related states to minimize view updates
    @Published public private(set) var mergeState: MergeDisplayState = .none

    // Current operation and target (for external use)
    @Published public private(set) var currentOperation: DragOperation = .none
    @Published public private(set) var currentTargetCell: CellCoordinate?

    // Internal state (not published)
    private var internalState: DragState = .idle

    public var state: DragState { internalState }

    // Configuration
    private let mergeHoverDuration: TimeInterval = 0.35  // Time to confirm merge
    private let folderOpenDelay: TimeInterval = 2.0      // Time to open folder when dragging over it
    private let velocityThreshold: CGFloat = 800        // pixels/second - fast = reorder

    // Internal state
    private var hoverTimer: Timer?
    private var folderOpenTimer: Timer?
    private var lastDragPosition: CGPoint = .zero
    private var lastDragTime: Date = .now
    private var currentVelocity: CGFloat = 0

    // Throttling
    private var lastOperation: DragOperation = .none
    private var lastTargetCell: CellCoordinate?
    private var lastUpdateTime: Date = .distantPast
    private let updateThrottleInterval: TimeInterval = 0.016 // ~60fps

    // Callbacks
    public var onOperationChanged: ((DragOperation, CellCoordinate?, Int) -> Void)?  // operation, targetCell, sourceIndex
    public var onMergeReady: ((UUID) -> Void)?
    public var onFolderOpen: ((UUID) -> Void)?  // Called when folder should open during drag

    public init() {}

    // MARK: - Public API

    public func startDrag() {
        transition(with: .startDrag)
        lastDragPosition = .zero
        lastDragTime = .now
        currentVelocity = 0
        lastOperation = .none
        lastTargetCell = nil
        lastUpdateTime = .distantPast
        currentOperation = .none
        currentTargetCell = nil
    }

    public func updateDrag(
        position: CGPoint,
        gridItems: [LauncherItem],
        draggingItemId: UUID,
        sourceIndex: Int,
        layout: GridLayoutParams,
        currentPage: Int
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

        // Step 1: Calculate hit position using pure function
        let hitResult = calculateHitPosition(
            position: position,
            currentPage: currentPage,
            layout: layout
        )

        // Step 2: Determine operation using pure function
        let operation = determineOperation(
            hitResult: hitResult,
            items: gridItems,
            draggingItemId: draggingItemId,
            layout: layout
        )

        // Get target info for state transitions
        let targetCell = hitResult.cell
        var targetId: UUID? = nil
        var isFolder = false

        if let cell = targetCell {
            let index = cell.toIndex(columnsCount: layout.columnsCount, appsPerPage: layout.appsPerPage)
            if index < gridItems.count {
                let targetItem = gridItems[index]
                if !targetItem.isEmpty && targetItem.id != draggingItemId {
                    targetId = targetItem.id
                    if case .folder = targetItem {
                        isFolder = true
                    }
                }
            }
        }

        // Skip if operation and target haven't changed (unless high velocity)
        if operation == lastOperation && targetCell == lastTargetCell && currentVelocity < velocityThreshold {
            return
        }
        lastOperation = operation
        lastTargetCell = targetCell

        // Update published state
        currentOperation = operation
        currentTargetCell = targetCell

        // High velocity always triggers reorder
        if currentVelocity > velocityThreshold {
            print("   ⚡ High velocity detected, forcing reorder")
            transition(with: .highVelocityDetected)
        }

        // Process operation change
        transition(with: .operationChanged(
            operation: operation,
            targetCell: targetCell,
            targetId: targetId,
            isFolder: isFolder
        ))

        // Notify callback for reorder operations
        if case .reorderCandidate = internalState {
            onOperationChanged?(operation, targetCell, sourceIndex)
        }
    }

    public func endDrag() -> (shouldMerge: Bool, targetId: UUID?, targetCell: CellCoordinate?) {
        let result: (shouldMerge: Bool, targetId: UUID?, targetCell: CellCoordinate?)

        print("🛑 endDrag called, current state=\(internalState)")

        switch internalState {
        case .mergeReady(let targetId, let targetCell):
            print("   ✅ State is mergeReady, will merge with \(targetId.uuidString.prefix(8))")
            result = (true, targetId, targetCell)
        case .mergeHovering(let targetId, let targetCell, let startTime):
            // Check if user has been hovering long enough (at least half the required time)
            let elapsedTime = Date().timeIntervalSince(startTime)
            let minimumHoverTime = mergeHoverDuration * 0.5
            if elapsedTime >= minimumHoverTime {
                print("   ✅ State is mergeHovering but elapsed time \(String(format: "%.2f", elapsedTime))s >= \(String(format: "%.2f", minimumHoverTime))s, will merge")
                result = (true, targetId, targetCell)
            } else {
                print("   ❌ State is mergeHovering but elapsed time too short")
                result = (false, nil, nil)
            }
        default:
            print("   ❌ State is NOT mergeReady")
            result = (false, nil, nil)
        }

        transition(with: .endDrag)
        cancelHoverTimer()
        currentOperation = .none
        currentTargetCell = nil
        return result
    }

    /// Get the current pending operation info (for applying on drop)
    public func getPendingOperation() -> (operation: DragOperation, targetCell: CellCoordinate?)? {
        switch internalState {
        case .reorderCandidate(let operation, let targetCell):
            return (operation, targetCell)
        case .mergeReady(_, let targetCell):
            return (.merge, targetCell)
        default:
            return nil
        }
    }

    public func reset() {
        internalState = .idle
        mergeState = .none
        cancelHoverTimer()
        cancelFolderOpenTimer()
        currentVelocity = 0
        lastOperation = .none
        lastTargetCell = nil
        currentOperation = .none
        currentTargetCell = nil
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
        case .mergeHovering(let targetId, _, _):
            newMergeState = .hovering(targetId: targetId)
        case .mergeReady(let targetId, _):
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
        case (.dragging, .operationChanged(let op, let cell, let targetId, let isFolder)):
            return handleOperationChange(op, cell: cell, targetId: targetId, isFolder: isFolder)
        case (.dragging, .endDrag):
            return .idle

        // From reorderCandidate
        case (.reorderCandidate, .operationChanged(let op, let cell, let targetId, let isFolder)):
            return handleOperationChange(op, cell: cell, targetId: targetId, isFolder: isFolder)
        case (.reorderCandidate, .endDrag):
            return .idle

        // From mergeHovering
        case (.mergeHovering(let targetId, let cell, _), .hoverTimerFired):
            onMergeReady?(targetId)
            return .mergeReady(targetId: targetId, targetCell: cell)
        case (.mergeHovering, .operationChanged(let op, let cell, let targetId, let isFolder)):
            cancelHoverTimer()
            return handleOperationChange(op, cell: cell, targetId: targetId, isFolder: isFolder)
        case (.mergeHovering, .highVelocityDetected):
            cancelHoverTimer()
            return .dragging
        case (.mergeHovering, .endDrag):
            cancelHoverTimer()
            return .idle

        // From mergeReady
        case (.mergeReady, .operationChanged(let op, let cell, let targetId, let isFolder)):
            cancelFolderOpenTimer()
            return handleOperationChange(op, cell: cell, targetId: targetId, isFolder: isFolder)
        case (.mergeReady, .highVelocityDetected):
            cancelFolderOpenTimer()
            return .dragging
        case (.mergeReady, .endDrag):
            cancelFolderOpenTimer()
            return .idle

        // Default - stay in current state
        default:
            return state
        }
    }

    private func handleOperationChange(_ operation: DragOperation, cell: CellCoordinate?, targetId: UUID?, isFolder: Bool) -> DragState {
        switch operation {
        case .none:
            cancelHoverTimer()
            cancelFolderOpenTimer()
            return .dragging

        case .merge:
            guard let targetId = targetId, let cell = cell else {
                return .dragging
            }

            // If target is a folder, immediately go to mergeReady
            if isFolder {
                print("   📁 Target is folder, immediately ready to merge")
                cancelHoverTimer()
                onMergeReady?(targetId)
                startFolderOpenTimer(targetId: targetId)
                return .mergeReady(targetId: targetId, targetCell: cell)
            }

            // For app targets, check if we're already hovering over this target
            if case .mergeHovering(let currentTargetId, _, _) = state, currentTargetId == targetId {
                return state  // Continue hovering
            }

            // Start hovering on new target
            cancelFolderOpenTimer()
            startHoverTimer()
            return .mergeHovering(targetId: targetId, targetCell: cell, startTime: Date())

        case .placeInEmpty, .insertLeft, .insertRight, .insertAbove, .insertBelow:
            guard let cell = cell else {
                return .dragging
            }
            cancelHoverTimer()
            cancelFolderOpenTimer()
            return .reorderCandidate(operation: operation, targetCell: cell)
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
