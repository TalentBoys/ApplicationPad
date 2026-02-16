//
//  FolderContainer.swift
//  LauncherCore
//
//  Folder container that does NOT allow nested folders
//

import Foundation

public final class FolderContainer: GridContainer, @unchecked Sendable {
    public let folderId: UUID
    public var pages: [Page]
    public let layout: GridLayout
    public let rules: ContainerRules

    public init(folderId: UUID, layout: GridLayout, pages: [Page]? = nil) {
        self.folderId = folderId
        self.layout = layout
        self.rules = ContainerRules(allowsFolder: false)  // Nested folders not allowed
        self.pages = pages ?? [Page.empty(rows: layout.rows, columns: layout.columns)]
    }

    /// Create from a list of apps (folders cannot contain folders)
    public convenience init(folderId: UUID, layout: GridLayout, apps: [AppItem]) {
        self.init(folderId: folderId, layout: layout)

        let slotsPerPage = layout.slotsPerPage
        let pageCount = max(1, (apps.count + slotsPerPage - 1) / slotsPerPage)

        pages = (0..<pageCount).map { pageIndex in
            var page = Page.empty(rows: layout.rows, columns: layout.columns)
            let startIndex = pageIndex * slotsPerPage
            let endIndex = min(startIndex + slotsPerPage, apps.count)

            for (i, app) in apps[startIndex..<endIndex].enumerated() {
                let position = GridPosition.fromLinearIndex(i, columns: layout.columns)
                page.setContent(.app(app), at: position)
            }
            return page
        }
    }

    /// Get all apps as a flat list
    public func flatApps() -> [AppItem] {
        pages.flatMap { $0.linearContents() }.compactMap { $0.asApp }
    }

    /// Convert to FolderItem
    public func toFolderItem(name: String) -> FolderItem {
        FolderItem(id: folderId, name: name, apps: flatApps())
    }
}
