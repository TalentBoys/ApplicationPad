//
//  RootContainer.swift
//  LauncherCore
//
//  Root launcher container that allows folders
//

import Foundation

public final class RootContainer: GridContainer, @unchecked Sendable {
    public var pages: [Page]
    public let layout: GridLayout
    public let rules: ContainerRules

    public init(layout: GridLayout, pages: [Page]? = nil) {
        self.layout = layout
        self.rules = ContainerRules(allowsFolder: true)
        self.pages = pages ?? [Page.empty(rows: layout.rows, columns: layout.columns)]
    }

    /// Create from a flat list of contents
    public convenience init(layout: GridLayout, contents: [SlotContent]) {
        self.init(layout: layout)

        let slotsPerPage = layout.slotsPerPage
        let pageCount = max(1, (contents.count + slotsPerPage - 1) / slotsPerPage)

        pages = (0..<pageCount).map { pageIndex in
            var page = Page.empty(rows: layout.rows, columns: layout.columns)
            let startIndex = pageIndex * slotsPerPage
            let endIndex = min(startIndex + slotsPerPage, contents.count)

            for (i, content) in contents[startIndex..<endIndex].enumerated() {
                let position = GridPosition.fromLinearIndex(i, columns: layout.columns)
                page.setContent(content, at: position)
            }
            return page
        }
    }

    /// Get all contents as a flat list (for compatibility)
    public func flatContents() -> [SlotContent] {
        pages.flatMap { $0.linearContents() }
    }
}
