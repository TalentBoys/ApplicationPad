//
//  ContainerTransfer.swift
//  LauncherCore
//
//  Logic for transferring items between containers (e.g., dragging out of folder)
//

import Foundation

/// Result of a transfer operation
public enum TransferResult: Sendable {
    case success
    case failed(reason: String)
}

/// Handles transfer of items between containers
public struct ContainerTransfer {

    /// Transfer an app from a folder to the root container
    /// - Parameters:
    ///   - app: The app to transfer
    ///   - fromFolder: The source folder container
    ///   - fromPosition: Position in the folder
    ///   - toRoot: The root container
    ///   - toPageIndex: Target page index in root
    ///   - toPosition: Target position in root
    ///   - intent: The drop intent
    /// - Returns: Transfer result
    public static func transferFromFolder(
        app: AppItem,
        fromFolder: FolderContainer,
        fromPosition: GridPosition,
        toRoot: RootContainer,
        toPageIndex: Int,
        toPosition: GridPosition,
        intent: DropIntent
    ) -> TransferResult {
        // Step 1: Remove from folder
        guard fromPosition.row < fromFolder.pages.count else {
            return .failed(reason: "Invalid source page")
        }

        var folderPages = fromFolder.pages
        if let pageIndex = findPageIndex(for: fromPosition, in: folderPages, layout: fromFolder.layout) {
            folderPages[pageIndex].clear(at: fromPosition)
            // Compact the folder pages
            compactPages(&folderPages, layout: fromFolder.layout)
            fromFolder.pages = folderPages
        }

        // Step 2: Insert into root container
        var rootPages = toRoot.pages
        let content = SlotContent.app(app)

        switch intent {
        case .intoEmpty(let position):
            if toPageIndex < rootPages.count {
                rootPages[toPageIndex].setContent(content, at: position)
            }

        case .insertBefore(let target):
            insertWithOverflow(
                content: content,
                at: target,
                pageIndex: toPageIndex,
                pages: &rootPages,
                layout: toRoot.layout
            )

        case .insertAfter(let target):
            let positions = rootPages[toPageIndex].linearPositions()
            if let idx = positions.firstIndex(of: target), idx + 1 < positions.count {
                let afterPosition = positions[idx + 1]
                insertWithOverflow(
                    content: content,
                    at: afterPosition,
                    pageIndex: toPageIndex,
                    pages: &rootPages,
                    layout: toRoot.layout
                )
            } else {
                // Insert at start of next page
                let nextPageIndex = toPageIndex + 1
                if nextPageIndex >= rootPages.count {
                    rootPages.append(Page.empty(rows: toRoot.layout.rows, columns: toRoot.layout.columns))
                }
                insertWithOverflow(
                    content: content,
                    at: GridPosition(row: 0, column: 0),
                    pageIndex: nextPageIndex,
                    pages: &rootPages,
                    layout: toRoot.layout
                )
            }

        case .merge(let target):
            // Merging when dragging out of folder - add to existing folder or create new
            if let existingContent = rootPages[toPageIndex].content(at: target) {
                switch existingContent {
                case .folder(var folder):
                    folder.slots.append(.app(app))
                    rootPages[toPageIndex].setContent(.folder(folder), at: target)
                case .app(let targetApp):
                    // Create new folder
                    let newFolder = FolderItem(
                        name: "New Folder",
                        apps: [targetApp, app]
                    )
                    rootPages[toPageIndex].setContent(.folder(newFolder), at: target)
                case .empty:
                    rootPages[toPageIndex].setContent(content, at: target)
                }
            }
        }

        toRoot.pages = rootPages
        return .success
    }

    /// Transfer an item from root to a folder
    /// - Parameters:
    ///   - app: The app to transfer
    ///   - fromRoot: The source root container
    ///   - fromPageIndex: Source page index
    ///   - fromPosition: Source position
    ///   - toFolder: The target folder container
    ///   - toPageIndex: Target page index in folder
    ///   - toPosition: Target position in folder
    /// - Returns: Transfer result
    public static func transferToFolder(
        app: AppItem,
        fromRoot: RootContainer,
        fromPageIndex: Int,
        fromPosition: GridPosition,
        toFolder: FolderContainer,
        toPageIndex: Int,
        toPosition: GridPosition
    ) -> TransferResult {
        // Step 1: Remove from root
        var rootPages = fromRoot.pages
        if fromPageIndex < rootPages.count {
            rootPages[fromPageIndex].clear(at: fromPosition)
            compactPages(&rootPages, layout: fromRoot.layout)
            fromRoot.pages = rootPages
        }

        // Step 2: Insert into folder
        var folderPages = toFolder.pages
        let content = SlotContent.app(app)

        if toPageIndex < folderPages.count {
            if let firstEmpty = folderPages[toPageIndex].firstEmptyPosition() {
                folderPages[toPageIndex].setContent(content, at: firstEmpty)
            } else {
                // Page is full, insert with overflow
                insertWithOverflow(
                    content: content,
                    at: toPosition,
                    pageIndex: toPageIndex,
                    pages: &folderPages,
                    layout: toFolder.layout
                )
            }
        }

        toFolder.pages = folderPages
        return .success
    }

    // MARK: - Private helpers

    private static func findPageIndex(
        for position: GridPosition,
        in pages: [Page],
        layout: GridLayout
    ) -> Int? {
        for (index, page) in pages.enumerated() {
            if page.slot(at: position) != nil {
                return index
            }
        }
        return nil
    }

    private static func insertWithOverflow(
        content: SlotContent,
        at position: GridPosition,
        pageIndex: Int,
        pages: inout [Page],
        layout: GridLayout
    ) {
        var carrying: SlotContent? = content
        var currentPageIndex = pageIndex

        if currentPageIndex < pages.count {
            carrying = pages[currentPageIndex].insertAndPush(content, at: position)
            currentPageIndex += 1
        }

        while let overflow = carrying {
            if currentPageIndex >= pages.count {
                pages.append(Page.empty(rows: layout.rows, columns: layout.columns))
            }
            carrying = pages[currentPageIndex].insertAndPush(
                overflow,
                at: GridPosition(row: 0, column: 0)
            )
            currentPageIndex += 1
        }
    }

    private static func compactPages(_ pages: inout [Page], layout: GridLayout) {
        // Remove empty trailing pages (keep at least one)
        while pages.count > 1 && pages.last?.isCompletelyEmpty == true {
            pages.removeLast()
        }
    }
}
