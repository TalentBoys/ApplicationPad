//
//  HitTestFunctionsTests.swift
//  LauncherCoreTests
//
//  Unit tests for HitTestFunctions
//

import XCTest
@testable import LauncherCore

final class HitTestFunctionsTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a simple AppItem for testing
    private func makeApp(_ name: String) -> AppItem {
        return AppItem(
            name: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            pinyinName: name.lowercased(),
            pinyinInitials: String(name.prefix(1)).lowercased()
        )
    }

    /// Create a 3x3 grid layout params
    private func make3x3Layout() -> GridLayoutParams {
        return GridLayoutParams(
            columnsCount: 3,
            rowsCount: 3,
            appsPerPage: 9,
            cellWidth: 100,
            cellHeight: 100,
            iconSize: 60,
            horizontalPadding: 50,
            topPadding: 50
        )
    }

    /// Create a 6x5 grid layout params
    private func make6x5Layout() -> GridLayoutParams {
        return GridLayoutParams(
            columnsCount: 6,
            rowsCount: 5,
            appsPerPage: 30,
            cellWidth: 100,
            cellHeight: 100,
            iconSize: 60,
            horizontalPadding: 50,
            topPadding: 50
        )
    }

    /// Extract app names from items for easy comparison
    private func itemNames(_ items: [LauncherItem]) -> [String] {
        return items.map { item in
            switch item {
            case .app(let app): return app.name
            case .folder(let folder): return "[\(folder.name)]"
            case .empty: return "empty"
            }
        }
    }

    // MARK: - UT1: InsertLeft - Full grid, source before target

    /// stable: A B C / D E F / G H I
    /// Drag B (index 1) insertLeft to F (index 5)
    /// B removed -> [A, empty, C, D, E, F, G, H, I]
    /// Insert at index 5, no empty after, squeeze left
    /// C→1, D→2, E→3, F→4, B→5... wait no
    /// Actually: C, D, E shift left to fill empty, B goes to index 4
    /// Expected: A C D / E B F / G H I
    func testUT1_InsertLeft_BToF_FullGrid() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "C", "D", "E", "B", "F", "G", "H", "I"],
                       "UT1: B insertLeft to F -> A C D / E B F / G H I")
    }

    // MARK: - UT2: InsertLeft - Full grid, source after target

    /// stable: A B C / D E F / G H I
    /// Drag H (index 7) insertLeft to F (index 5)
    /// H removed -> [A, B, C, D, E, F, G, empty, I]
    /// Insert at index 5, empty at index 7, squeeze right
    /// F→6, G→7, H→5
    /// Expected: A B C / D E H / F G I
    func testUT2_InsertLeft_HToF_FullGrid() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position
        let sourceIndex = 7 // H

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "B", "C", "D", "E", "H", "F", "G", "I"],
                       "UT2: H insertLeft to F -> A B C / D E H / F G I")
    }

    // MARK: - UT3: InsertRight - Prefer squeeze right when possible

    /// stable: A empty C / D E F / G H I
    /// Drag H (index 7) insertRight to E (index 4)
    /// H removed -> [A, empty, C, D, E, F, G, empty, I]
    /// Insert at index 5 (E's right), empty at index 7, squeeze right
    /// F→6, G→7, H→5
    /// Expected: A empty C / D E H / F G I
    func testUT3_InsertRight_HToE_PreferSqueezeRight() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .empty(UUID()), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 1) // E's position
        let sourceIndex = 7 // H

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "E", "H", "F", "G", "I"],
                       "UT3: H insertRight to E -> A empty C / D E H / F G I (prefer squeeze right)")
    }

    // MARK: - UT4: InsertRight - Squeeze left when right is full

    /// stable: A empty C / D E F / G H I
    /// Drag D (index 3) insertRight to E (index 4)
    /// D removed -> [A, empty, C, empty, E, F, G, H, I]
    /// Insert at index 5 (E's right), no empty after (F G H I full), squeeze left
    /// E→3 (fills D's empty), D→4
    /// Expected: A empty C / E D F / G H I
    func testUT4_InsertRight_DToE_SqueezeLeft() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .empty(UUID()), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 1) // E's position
        let sourceIndex = 3 // D

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "E", "D", "F", "G", "H", "I"],
                       "UT4: D insertRight to E -> A empty C / E D F / G H I (squeeze left)")
    }

    // MARK: - UT5: InsertRight to row-end target - Prefer squeeze left

    /// stable: A empty C / D E F / G H empty
    /// Drag D (index 3) insertRight to F (index 5) - F is row-end
    /// D removed -> [A, empty, C, empty, E, F, G, H, empty]
    /// Insert at index 6 (F's right), F is row-end so prefer squeeze left
    /// E→3, F→4, D→5
    /// Expected: A empty C / E F D / G H empty
    func testUT5_InsertRight_DToF_RowEnd_PreferSqueezeLeft() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .empty(UUID()), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .empty(UUID())
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position (row-end)
        let sourceIndex = 3 // D

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "E", "F", "D", "G", "H", "empty"],
                       "UT5: D insertRight to F (row-end) -> A empty C / E F D / G H empty (prefer squeeze left)")
    }

    // MARK: - UT6: InsertRight to row-end - Squeeze right when source > target

    /// stable: A B C / D E F / G H empty
    /// Drag H (index 7) insertRight to F (index 5) - F is row-end
    /// H removed -> [A, B, C, D, E, F, G, empty, empty]
    /// source (7) > target (5), so squeeze right
    /// F→6, G→7, H→5
    /// Expected: A B C / D E H / F G empty
    func testUT6_InsertRight_HToF_RowEnd_SqueezeRight() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .empty(UUID())
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position (row-end)
        let sourceIndex = 7 // H

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "B", "C", "D", "E", "H", "F", "G", "empty"],
                       "UT6: H insertRight to F (row-end) -> A B C / D E H / F G empty (squeeze right)")
    }

    // MARK: - UT7: InsertRight - Cross-row with empty slot

    /// stable: A B C / D empty F / G H I
    /// Drag B (index 1) insertRight to H (index 7)
    /// B removed -> [A, empty, C, D, empty, F, G, H, I]
    /// Insert at index 8 (H's right), no empty after, squeeze left
    /// Find empty at index 4, shift F→4, G→5, H→6, B→7
    /// Expected: A empty C / D F G / H B I
    func testUT7_InsertRight_BToH_CrossRow() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .empty(UUID()), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 2, column: 1) // H's position
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "F", "G", "H", "B", "I"],
                       "UT7: B insertRight to H -> A empty C / D F G / H B I (squeeze left)")
    }

    // MARK: - UT8-UT11: Continuous drag B around grid with empty slot
    // stable: A B C / D empty F / G H I
    // Key insight: No icons should move to next page since this page has enough space

    /// UT8: Drag B to left of F
    /// B removed -> [A, empty, C, D, empty, F, G, H, I]
    /// insertLeft at F (index 5), F can't shift right (G H I full), but empty at 4 is available
    /// B takes position 4 (empty slot before F)
    /// Expected: A empty C / D B F / G H I
    func testUT8_InsertLeft_BToF_WithEmptySlot() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .empty(UUID()), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "B", "F", "G", "H", "I"],
                       "UT8: B insertLeft to F -> A empty C / D B F / G H I (B fills empty at 4)")
    }

    /// UT9: Drag B to right of F (F is row-end)
    /// B removed -> [A, empty, C, D, empty, F, G, H, I]
    /// insertRight at F (row-end, source < target), prefer squeeze left
    /// F→4, B→5
    /// Expected: A empty C / D F B / G H I
    func testUT9_InsertRight_BToF_RowEnd() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .empty(UUID()), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 1, column: 2) // F's position (row-end)
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "F", "B", "G", "H", "I"],
                       "UT9: B insertRight to F (row-end) -> A empty C / D F B / G H I")
    }

    /// UT10: Drag B to left of G
    /// B removed -> [A, empty, C, D, empty, F, G, H, I]
    /// insertLeft at G (index 6), G is at leftmost column (col 0)
    /// No empty after G (H I full), but G is row-start so items shift forward (up)
    /// F→4, G→5, B→6
    /// Expected: A empty C / D F G / B H I
    func testUT10_InsertLeft_BToG_RowStart() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .empty(UUID()), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 2, column: 0) // G's position (row-start)
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "F", "G", "B", "H", "I"],
                       "UT10: B insertLeft to G (row-start) -> A empty C / D F G / B H I (G shifts forward)")
    }

    /// UT11: Drag B to right of I
    /// B removed -> [A, empty, C, D, empty, F, G, H, I]
    /// insertRight at I (row-end, source < target), prefer squeeze left
    /// Find empty at 4, shift F→4, G→5, H→6, I→7, B→8
    /// Expected: A empty C / D F G / H I B
    func testUT11_InsertRight_BToI_RowEnd() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .empty(UUID()), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        let targetCell = CellCoordinate(page: 0, row: 2, column: 2) // I's position (row-end)
        let sourceIndex = 1 // B

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "empty", "C", "D", "F", "G", "H", "I", "B"],
                       "UT11: B insertRight to I (row-end) -> A empty C / D F G / H I B")
    }

    // MARK: - Continuous Drag Test

    func testContinuousDrag_BAroundGrid() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()
        let sourceIndex = 1  // B - this never changes during drag!

        // Step 1: Drag B to left of C (insertLeft, target index 2)
        let targetC = CellCoordinate(page: 0, row: 0, column: 2)
        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetC,
            sourceIndex: sourceIndex,
            layout: layout
        )

        var result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "B", "C", "D", "E", "F", "G", "H", "I"],
                       "Step 1: B insertLeft to C - B already at C's left, no change")

        // Step 2: Drag B to right of C (insertRight, target index 2)
        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetC,
            sourceIndex: sourceIndex,
            layout: layout
        )

        result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "C", "B", "D", "E", "F", "G", "H", "I"],
                       "Step 2: B insertRight to C - C shifts left, B goes to index 2")

        // Step 3: Drag B to right of E (insertRight, target index 4)
        let targetE = CellCoordinate(page: 0, row: 1, column: 1)
        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetE,
            sourceIndex: sourceIndex,
            layout: layout
        )

        result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "C", "D", "E", "B", "F", "G", "H", "I"],
                       "Step 3: B insertRight to E - C,D,E shift left, B goes to index 4")

        // Step 4: Release drag
        await gridState.commitPreview()
        let stableResult = await itemNames(gridState.stableItems)
        XCTAssertEqual(stableResult, ["A", "C", "D", "E", "B", "F", "G", "H", "I"])
    }

    // MARK: - UT12: Large grid (6x5) continuous drag test

    /// stable layout (6 columns x 5 rows):
    /// A1 A2 A3 A4 A5 A6      (indices 0-5)
    /// B1 B2 B3 B4 B5 B6      (indices 6-11)
    /// C1 C2 C3 C4 empty C6   (indices 12-17, empty at 16)
    /// D1 D2 D3 D4 D5 D6      (indices 18-23)
    /// E1 E2 E3 E4 E5 E6      (indices 24-29)
    ///
    /// Test continuous drag of B5 (index 10)
    func testUT12_LargeGrid_ContinuousDrag() async {
        let layout = make6x5Layout()

        // Create 6x5 grid with empty at position 16 (row 2, col 4)
        let gridState = await GridState(items: [
            // Row 0
            .app(makeApp("A1")), .app(makeApp("A2")), .app(makeApp("A3")),
            .app(makeApp("A4")), .app(makeApp("A5")), .app(makeApp("A6")),
            // Row 1
            .app(makeApp("B1")), .app(makeApp("B2")), .app(makeApp("B3")),
            .app(makeApp("B4")), .app(makeApp("B5")), .app(makeApp("B6")),
            // Row 2
            .app(makeApp("C1")), .app(makeApp("C2")), .app(makeApp("C3")),
            .app(makeApp("C4")), .empty(UUID()), .app(makeApp("C6")),
            // Row 3
            .app(makeApp("D1")), .app(makeApp("D2")), .app(makeApp("D3")),
            .app(makeApp("D4")), .app(makeApp("D5")), .app(makeApp("D6")),
            // Row 4
            .app(makeApp("E1")), .app(makeApp("E2")), .app(makeApp("E3")),
            .app(makeApp("E4")), .app(makeApp("E5")), .app(makeApp("E6"))
        ])

        await gridState.startPreview()
        let sourceIndex = 10 // B5 - never changes during drag

        // Step 1: Drag B5 insertLeft to C6 (index 17)
        // B5 removed -> empty at 10
        // insertLeft at 17, empty at 16 is right before target
        // B5 takes position 16
        // Expected:
        // A1 A2 A3 A4 A5 A6
        // B1 B2 B3 B4 empty B6
        // C1 C2 C3 C4 B5 C6
        // D1 D2 D3 D4 D5 D6
        // E1 E2 E3 E4 E5 E6
        let targetC6 = CellCoordinate(page: 0, row: 2, column: 5) // C6's position
        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetC6,
            sourceIndex: sourceIndex,
            layout: layout
        )

        var result = await itemNames(gridState.items)
        XCTAssertEqual(result, [
            "A1", "A2", "A3", "A4", "A5", "A6",
            "B1", "B2", "B3", "B4", "empty", "B6",
            "C1", "C2", "C3", "C4", "B5", "C6",
            "D1", "D2", "D3", "D4", "D5", "D6",
            "E1", "E2", "E3", "E4", "E5", "E6"
        ], "Step 1: B5 insertLeft to C6 -> B5 fills empty slot at 16")

        // Step 2: Drag B5 insertLeft to D5 (index 22)
        // Remember: preview recalculates from stable each time!
        // B5 removed from stable -> empty at 10
        // insertLeft at 22 (D5), no empty after, find empty at 16
        // Shift left: C6→16, D1→17, D2→18, D3→19, D4→20
        // B5 goes to position 21
        // Expected:
        // A1 A2 A3 A4 A5 A6
        // B1 B2 B3 B4 empty B6
        // C1 C2 C3 C4 C6 D1
        // D2 D3 D4 B5 D5 D6
        // E1 E2 E3 E4 E5 E6
        let targetD5 = CellCoordinate(page: 0, row: 3, column: 4) // D5's position
        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetD5,
            sourceIndex: sourceIndex,
            layout: layout
        )

        result = await itemNames(gridState.items)
        XCTAssertEqual(result, [
            "A1", "A2", "A3", "A4", "A5", "A6",
            "B1", "B2", "B3", "B4", "empty", "B6",
            "C1", "C2", "C3", "C4", "C6", "D1",
            "D2", "D3", "D4", "B5", "D5", "D6",
            "E1", "E2", "E3", "E4", "E5", "E6"
        ], "Step 2: B5 insertLeft to D5 -> C6,D1,D2,D3,D4 shift left, B5 at 21")
    }

    // MARK: - UT13: Page boundary - insertRight should not push items to next page

    /// stable layout (6 columns x 5 rows, 30 items per page):
    /// Row 0: A1  A2  A3  A4  A5  A6       (0-5)
    /// Row 1: B1  B2  B3  B4  B5  B6       (6-11)
    /// Row 2: C1  C2  C3  C4  ·   C6       (12-17, empty at 16)
    /// Row 3: D1  D2  D3  D4  D5  D6       (18-23)
    /// Row 4: E1  E2  E3  E4  E5  E6       (24-29)
    ///
    /// Drag C4 (index 15) insertRight to D4 (index 21)
    /// Page 0 has no empty after index 22, but has empty at 16
    /// Should shift left within page, NOT push E6 to page 1
    ///
    /// Expected result:
    /// Row 0: A1  A2  A3  A4  A5  A6
    /// Row 1: B1  B2  B3  B4  B5  B6
    /// Row 2: C1  C2  C3  ·   C6  D1       (C4 removed, items shift left)
    /// Row 3: D2  D3  D4  C4  D5  D6       (C4 inserted after D4)
    /// Row 4: E1  E2  E3  E4  E5  E6       (E6 stays on page 0!)
    func testUT13_InsertRight_PageBoundary_NoOverflow() async {
        let layout = make6x5Layout()

        // Create 6x5 grid with empty at position 16 (row 2, col 4)
        let gridState = await GridState(items: [
            // Row 0
            .app(makeApp("A1")), .app(makeApp("A2")), .app(makeApp("A3")),
            .app(makeApp("A4")), .app(makeApp("A5")), .app(makeApp("A6")),
            // Row 1
            .app(makeApp("B1")), .app(makeApp("B2")), .app(makeApp("B3")),
            .app(makeApp("B4")), .app(makeApp("B5")), .app(makeApp("B6")),
            // Row 2
            .app(makeApp("C1")), .app(makeApp("C2")), .app(makeApp("C3")),
            .app(makeApp("C4")), .empty(UUID()), .app(makeApp("C6")),
            // Row 3
            .app(makeApp("D1")), .app(makeApp("D2")), .app(makeApp("D3")),
            .app(makeApp("D4")), .app(makeApp("D5")), .app(makeApp("D6")),
            // Row 4
            .app(makeApp("E1")), .app(makeApp("E2")), .app(makeApp("E3")),
            .app(makeApp("E4")), .app(makeApp("E5")), .app(makeApp("E6"))
        ])

        await gridState.startPreview()

        // Drag C4 (index 15) insertRight to D4 (index 21)
        let targetCell = CellCoordinate(page: 0, row: 3, column: 3) // D4's position
        let sourceIndex = 15 // C4

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        let result = await itemNames(gridState.items)
        XCTAssertEqual(result, [
            "A1", "A2", "A3", "A4", "A5", "A6",
            "B1", "B2", "B3", "B4", "B5", "B6",
            "C1", "C2", "C3", "empty", "C6", "D1",
            "D2", "D3", "D4", "C4", "D5", "D6",
            "E1", "E2", "E3", "E4", "E5", "E6"
        ], "UT13: C4 insertRight to D4 -> items shift left within page, E6 stays on page 0")
    }
}
