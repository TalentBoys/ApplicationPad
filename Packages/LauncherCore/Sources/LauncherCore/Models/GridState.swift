//
//  GridState.swift
//  LauncherCore
//
//  Manages stable and preview state for drag operations
//  Design: UI State = preview ?? stable
//  - preview is initially nil
//  - On drag start: preview = copy of stable
//  - All reorder/merge operations happen on preview
//  - On drag end: if changed -> stable = preview, preview = nil (commit)
//                 if unchanged -> preview = nil (cancel)
//

import Foundation

/// Manages the dual-layer state model for grid items
/// - stable: The committed state (source of truth)
/// - preview: The temporary preview during drag operations
@MainActor
public final class GridState: ObservableObject {
    /// The stable (committed) state
    @Published private var stable: [LauncherItem]

    /// The preview state during drag (nil when not dragging)
    @Published private var preview: [LauncherItem]?

    /// Track if any changes were made during this drag session
    private var hasChanges: Bool = false

    /// Current layout columns count for logging (set via setLayoutForLogging)
    private var logColumnsCount: Int = 6

    /// Current layout rows count for logging (set via setLayoutForLogging)
    private var logRowsCount: Int = 5

    /// Enable/disable layout logging
    public var enableLayoutLogging: Bool = false

    public init(items: [LauncherItem] = []) {
        self.stable = items
        self.preview = nil
    }

    // MARK: - Public API

    /// The items to render (preview if available, otherwise stable)
    public var items: [LauncherItem] {
        preview ?? stable
    }

    /// The stable items (committed state)
    public var stableItems: [LauncherItem] {
        stable
    }

    /// Whether currently in preview mode (dragging)
    public var isPreviewActive: Bool {
        preview != nil
    }

    /// Whether changes were made during current preview
    public var previewHasChanges: Bool {
        hasChanges
    }

    // MARK: - Layout Logging

    /// Set layout params for logging purposes
    public func setLayoutForLogging(columnsCount: Int, rowsCount: Int) {
        self.logColumnsCount = columnsCount
        self.logRowsCount = rowsCount
    }

    /// Format items as a 2D grid string, separated by pages
    private func formatGridLayout(_ items: [LauncherItem], columnsCount: Int, rowsCount: Int) -> String {
        guard !items.isEmpty else { return "(empty grid)" }

        let appsPerPage = columnsCount * rowsCount
        let totalPages = max(1, Int(ceil(Double(items.count) / Double(appsPerPage))))

        var pageStrings: [String] = []

        for page in 0..<totalPages {
            let pageStart = page * appsPerPage
            let pageEnd = min(pageStart + appsPerPage, items.count)

            var lines: [String] = []
            lines.append("--- Page \(page) ---")

            for row in 0..<rowsCount {
                var rowItems: [String] = []
                for col in 0..<columnsCount {
                    let index = pageStart + row * columnsCount + col
                    let name: String
                    if index < pageEnd {
                        let item = items[index]
                        switch item {
                        case .app(let app):
                            name = app.name
                        case .folder(let folder):
                            name = "[\(folder.name)]"
                        case .empty:
                            name = "·"
                        }
                    } else {
                        name = ""  // Beyond array bounds
                    }
                    // Pad to 6 characters for alignment
                    let padded = name.padding(toLength: 6, withPad: " ", startingAt: 0)
                    rowItems.append(padded)
                }
                lines.append(rowItems.joined(separator: " "))
            }

            pageStrings.append(lines.joined(separator: "\n"))
        }

        return pageStrings.joined(separator: "\n\n")
    }

    /// Log current layout state
    private func logLayout(label: String) {
        guard enableLayoutLogging else { return }

        let currentItems = preview ?? stable
        let layoutStr = formatGridLayout(currentItems, columnsCount: logColumnsCount, rowsCount: logRowsCount)
        print("📊 \(label):\n\(layoutStr)\n")
    }

    // MARK: - State Management

    /// Update stable state directly (for non-drag operations like initial load)
    public func setStable(_ items: [LauncherItem]) {
        stable = items
        preview = nil
        hasChanges = false
    }

    /// Start preview mode: copy stable to preview
    /// Call this when drag starts
    public func startPreview() {
        preview = stable
        hasChanges = false
        logLayout(label: "Preview Started (from stable)")
    }

    /// Commit preview to stable
    /// Call this when drag ends with valid changes
    public func commitPreview() {
        if let previewItems = preview {
            stable = previewItems
        }
        preview = nil
        hasChanges = false
        logLayout(label: "Committed to Stable")
    }

    /// Cancel preview and revert to stable
    /// Call this when drag ends without changes or is cancelled
    public func cancelPreview() {
        preview = nil
        hasChanges = false
        logLayout(label: "Preview Cancelled (reverted to stable)")
    }

    /// Set preview items directly (for HitTestFunctions)
    public func setPreviewItems(_ items: [LauncherItem]) {
        preview = items
        hasChanges = true
        logLayout(label: "Preview Updated")
    }

    // MARK: - Preview Operations (all operate on preview)

    /// Reorder: move item from one index to another
    /// Returns true if reorder was performed
    @discardableResult
    public func reorder(from sourceIndex: Int, to targetIndex: Int) -> Bool {
        guard var previewItems = preview else { return false }
        guard sourceIndex != targetIndex else { return false }
        guard sourceIndex >= 0 && sourceIndex < previewItems.count else { return false }
        guard targetIndex >= 0 && targetIndex <= previewItems.count else { return false }

        let item = previewItems.remove(at: sourceIndex)
        let insertIndex = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex
        previewItems.insert(item, at: min(insertIndex, previewItems.count))

        preview = previewItems
        hasChanges = true
        return true
    }

    /// Swap: exchange two items (useful for swapping with empty slots)
    /// Returns true if swap was performed
    @discardableResult
    public func swap(index1: Int, index2: Int) -> Bool {
        guard var previewItems = preview else { return false }
        guard index1 != index2 else { return false }
        guard index1 >= 0 && index1 < previewItems.count else { return false }
        guard index2 >= 0 && index2 < previewItems.count else { return false }

        previewItems.swapAt(index1, index2)
        preview = previewItems
        hasChanges = true
        return true
    }

    /// Merge: combine dragging item into target (create folder or add to folder)
    /// Returns true if merge was performed
    @discardableResult
    public func merge(sourceIndex: Int, intoTargetIndex targetIndex: Int) -> Bool {
        guard var previewItems = preview else { return false }
        guard sourceIndex != targetIndex else { return false }
        guard sourceIndex >= 0 && sourceIndex < previewItems.count else { return false }
        guard targetIndex >= 0 && targetIndex < previewItems.count else { return false }

        let sourceItem = previewItems[sourceIndex]
        let targetItem = previewItems[targetIndex]

        // Get apps from source
        var appsToAdd: [AppItem] = []
        switch sourceItem {
        case .app(let app):
            appsToAdd.append(app)
        case .folder(let folder):
            appsToAdd.append(contentsOf: folder.apps)
        case .empty:
            return false
        }

        // Merge into target
        let newItem: LauncherItem
        switch targetItem {
        case .folder(var folder):
            // Add to existing folder
            folder.apps.append(contentsOf: appsToAdd)
            newItem = .folder(folder)
        case .app(let app):
            // Create new folder
            var apps = [app]
            apps.append(contentsOf: appsToAdd)
            newItem = .folder(FolderItem(name: "Folder", apps: apps))
        case .empty:
            return false
        }

        // Replace source with empty, update target with merged item
        previewItems[sourceIndex] = .empty(UUID())
        previewItems[targetIndex] = newItem

        preview = previewItems
        hasChanges = true
        return true
    }

    /// Insert item at index (for drag from outside)
    @discardableResult
    public func insert(_ item: LauncherItem, at index: Int) -> Bool {
        guard var previewItems = preview else { return false }
        guard index >= 0 && index <= previewItems.count else { return false }

        previewItems.insert(item, at: index)
        preview = previewItems
        hasChanges = true
        return true
    }

    /// Remove item at index
    @discardableResult
    public func remove(at index: Int) -> LauncherItem? {
        guard var previewItems = preview else { return nil }
        guard index >= 0 && index < previewItems.count else { return nil }

        let removed = previewItems.remove(at: index)
        preview = previewItems
        hasChanges = true
        return removed
    }

    /// Replace item at index
    @discardableResult
    public func replace(at index: Int, with item: LauncherItem) -> Bool {
        guard var previewItems = preview else { return false }
        guard index >= 0 && index < previewItems.count else { return false }

        previewItems[index] = item
        preview = previewItems
        hasChanges = true
        return true
    }

    /// Update item at index (for folder updates etc.)
    /// Works on stable state directly (for non-drag operations)
    public func updateStable(at index: Int, with item: LauncherItem) {
        guard index >= 0 && index < stable.count else { return }
        stable[index] = item
    }

    /// Remove from stable (for non-drag operations)
    public func removeFromStable(at index: Int) {
        guard index >= 0 && index < stable.count else { return }
        stable.remove(at: index)
    }
}
