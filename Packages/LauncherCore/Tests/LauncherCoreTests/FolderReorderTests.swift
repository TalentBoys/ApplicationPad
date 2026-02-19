//
//  FolderReorderTests.swift
//  LauncherCoreTests
//
//  Unit tests for folder app reordering logic
//  NOTE: Since folder now uses the same GridState.applyOperation logic as launcher,
//  many tests from HitTestFunctionsTests also apply to folder behavior.
//

import XCTest
@testable import LauncherCore

final class FolderReorderTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create mock folder items (apps only, no nested folders)
    private func createFolderItems(_ names: [String]) -> [LauncherItem] {
        names.map { name in
            if name == "·" {
                return .empty(UUID())
            } else {
                return .app(AppItem(
                    id: UUID(),
                    name: name,
                    url: URL(fileURLWithPath: "/Applications/\(name).app"),
                    pinyinName: name.lowercased(),
                    pinyinInitials: String(name.prefix(1)).lowercased()
                ))
            }
        }
    }

    /// Format items as string array for easier comparison
    private func formatItems(_ items: [LauncherItem]) -> [String] {
        items.map { item in
            switch item {
            case .app(let app): return app.name
            case .folder(let f): return "[\(f.name)]"
            case .empty: return "·"
            }
        }
    }

    // MARK: - FolderItem Slot Management Tests

    /// Test that FolderItem.apps returns only non-empty apps
    func testFolderItem_Apps_FiltersEmpty() {
        let folder = FolderItem(
            name: "Test",
            slots: createFolderItems(["A", "·", "B", "·", "C"])
        )
        XCTAssertEqual(folder.apps.count, 3)
        XCTAssertEqual(folder.apps.map { $0.name }, ["A", "B", "C"])
    }

    /// Test that FolderItem.compact removes empty slots
    func testFolderItem_Compact() {
        var folder = FolderItem(
            name: "Test",
            slots: createFolderItems(["A", "·", "B", "·", "C"])
        )
        XCTAssertEqual(folder.slots.count, 5)

        folder.compact()

        XCTAssertEqual(folder.slots.count, 3)
        XCTAssertEqual(formatItems(folder.slots), ["A", "B", "C"])
    }

    /// Test FolderItem initialization with apps
    func testFolderItem_InitWithApps() {
        let apps = [
            AppItem(id: UUID(), name: "A", url: URL(fileURLWithPath: "/A.app"), pinyinName: "a", pinyinInitials: "a"),
            AppItem(id: UUID(), name: "B", url: URL(fileURLWithPath: "/B.app"), pinyinName: "b", pinyinInitials: "b")
        ]
        let folder = FolderItem(name: "Test", apps: apps)

        XCTAssertEqual(folder.slots.count, 2)
        XCTAssertEqual(folder.apps.count, 2)
        XCTAssertEqual(folder.apps[0].name, "A")
        XCTAssertEqual(folder.apps[1].name, "B")
    }

    // MARK: - GridState Integration Tests for Folder

    /// Test that folder drag uses GridState.applyOperation correctly
    /// This simulates dragging B to the left of F in a 2x3 folder grid
    @MainActor
    func testFolderDrag_InsertLeft_BToF() async throws {
        // Folder: A B C
        //         D E F
        let items = createFolderItems(["A", "B", "C", "D", "E", "F"])
        let gridState = GridState(items: items)

        // Start preview mode
        gridState.startPreview()

        // Layout params for 2x3 folder (like launcher but smaller)
        let layout = GridLayoutParams(
            columnsCount: 3,
            rowsCount: 2,
            appsPerPage: 6,
            cellWidth: 100,
            cellHeight: 100,
            iconSize: 64,
            horizontalPadding: 0,
            topPadding: 0
        )

        // Drag B (index 1) to left of F (index 5)
        // F is at cell (2, 1), center at (250, 150)
        // For insertLeft, position should be in the left region: x < 250 - 32 = 218
        // Cell (2, 1) spans x: 200-300, center: 250
        // Left region: x < 250 - 32 (half icon size)
        let hitResult = calculateHitPosition(
            position: CGPoint(x: 205, y: 150),  // Left region of F's cell
            currentPage: 0,
            layout: layout
        )

        // Source index is B's position in stable (index 1)
        let operation = determineOperation(
            hitResult: hitResult,
            items: gridState.items,
            draggingItemId: items[1].id,  // B
            layout: layout
        )

        XCTAssertEqual(operation, .insertLeft, "Should be insertLeft when in left region of cell")

        // Apply operation
        gridState.applyOperation(
            operation: operation,
            targetCell: hitResult.cell,
            sourceIndex: 1,  // B's original position
            layout: layout
        )

        // Expected: A · C D E B F (B moved to left of F, leaving empty at position 1)
        // Or with shifting: A C D E B F
        let result = formatItems(gridState.items)

        // B should be somewhere before F
        XCTAssertTrue(result.contains("B"), "B should still be in the grid")
        if let bIndex = result.firstIndex(of: "B"), let fIndex = result.firstIndex(of: "F") {
            XCTAssertLessThan(bIndex, fIndex, "B should be before F")
        }
    }

    /// Test that folder drag handles empty slots correctly
    @MainActor
    func testFolderDrag_PlaceInEmpty() async throws {
        // Folder: A B ·
        //         D E F
        let items = createFolderItems(["A", "B", "·", "D", "E", "F"])
        let gridState = GridState(items: items)
        gridState.startPreview()

        let layout = GridLayoutParams(
            columnsCount: 3,
            rowsCount: 2,
            appsPerPage: 6,
            cellWidth: 100,
            cellHeight: 100,
            iconSize: 64,
            horizontalPadding: 0,
            topPadding: 0
        )

        // Drag B (index 1) to empty slot (index 2)
        let hitResult = calculateHitPosition(
            position: CGPoint(x: 250, y: 50),  // Center of position 2
            currentPage: 0,
            layout: layout
        )

        let operation = determineOperation(
            hitResult: hitResult,
            items: gridState.items,
            draggingItemId: items[1].id,  // B
            layout: layout
        )

        XCTAssertEqual(operation, .placeInEmpty)

        gridState.applyOperation(
            operation: operation,
            targetCell: hitResult.cell,
            sourceIndex: 1,
            layout: layout
        )

        // Expected: A · B D E F (B swapped with empty)
        let result = formatItems(gridState.items)
        XCTAssertEqual(result[2], "B", "B should be at position 2")
        XCTAssertEqual(result[1], "·", "Position 1 should be empty")
    }

    // MARK: - Legacy Tests (kept for reference)
    // These test the old simple reorder algorithm that was used before GridState integration

    /// Simulate old folder reorder logic (kept for comparison)
    private func reorderApps(_ apps: [String], from fromIndex: Int, to toIndex: Int) -> [String] {
        guard fromIndex != toIndex else { return apps }

        var result = apps
        let movedApp = result.remove(at: fromIndex)
        let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        result.insert(movedApp, at: min(insertIndex, result.count))
        return result
    }

    /// Basic reorder test (legacy algorithm)
    func testLegacy_Reorder_BToPosition4() {
        let apps = ["A", "B", "C", "D", "E", "F"]
        let result = reorderApps(apps, from: 1, to: 4)
        XCTAssertEqual(result, ["A", "C", "D", "B", "E", "F"])
    }

    /// Legacy: drag to same position
    func testLegacy_Reorder_SamePosition() {
        let apps = ["A", "B", "C", "D", "E", "F"]
        let result = reorderApps(apps, from: 2, to: 2)
        XCTAssertEqual(result, apps)
    }
}
