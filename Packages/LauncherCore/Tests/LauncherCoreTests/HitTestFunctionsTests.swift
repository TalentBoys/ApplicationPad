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

    // MARK: - Test: Continuous Drag (Full Grid)

    /// Test continuous dragging B across the grid
    /// stable: A B C / D E F / G H I (never changes during drag)
    ///
    /// Step 1: Drag B to left of C → insertLeft, target=C(index 2), source=B(index 1)
    ///         preview should be: A B C D E F G H I (no change, B is already left of C)
    ///
    /// Step 2: Drag B to right of C → insertRight, target=C(index 2), source=B(index 1)
    ///         preview should be: A C B D E F G H I
    ///
    /// Step 3: Drag B to right of E → insertRight, target=E(index 4), source=B(index 1)
    ///         preview should be: A C D E B F G H I
    ///
    /// Step 4: Release drag → stable = preview, preview = nil
    func testContinuousDrag_BAroundGrid() async {
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        // Start drag
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

        // Verify stable unchanged
        var stableResult = await itemNames(gridState.stableItems)
        XCTAssertEqual(stableResult, ["A", "B", "C", "D", "E", "F", "G", "H", "I"],
                       "Stable should never change during drag")

        // Step 2: Drag B to right of C (insertRight, target index 2)
        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetC,
            sourceIndex: sourceIndex,  // Still 1, always refers to stable
            layout: layout
        )

        result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "C", "B", "D", "E", "F", "G", "H", "I"],
                       "Step 2: B insertRight to C - C shifts left, B goes to index 2")

        // Verify stable unchanged
        stableResult = await itemNames(gridState.stableItems)
        XCTAssertEqual(stableResult, ["A", "B", "C", "D", "E", "F", "G", "H", "I"],
                       "Stable should never change during drag")

        // Step 3: Drag B to right of E (insertRight, target index 4)
        let targetE = CellCoordinate(page: 0, row: 1, column: 1)
        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetE,
            sourceIndex: sourceIndex,  // Still 1, always refers to stable
            layout: layout
        )

        result = await itemNames(gridState.items)
        XCTAssertEqual(result, ["A", "C", "D", "E", "B", "F", "G", "H", "I"],
                       "Step 3: B insertRight to E - C,D,E shift left, B goes to index 4")

        // Verify stable unchanged
        stableResult = await itemNames(gridState.stableItems)
        XCTAssertEqual(stableResult, ["A", "B", "C", "D", "E", "F", "G", "H", "I"],
                       "Stable should never change during drag")

        // Step 4: Release drag - commit preview to stable
        await gridState.commitPreview()

        // Now stable should equal the final preview
        stableResult = await itemNames(gridState.stableItems)
        XCTAssertEqual(stableResult, ["A", "C", "D", "E", "B", "F", "G", "H", "I"],
                       "Step 4: After commit, stable = final preview")

        // Preview should be nil (items returns stable)
        let isPreviewActive = await gridState.isPreviewActive
        XCTAssertFalse(isPreviewActive, "Preview should be nil after commit")
    }

    // MARK: - Test 1: Insert Left (D into B's position)

    /// 3x3 layout:
    /// A B C
    /// D E F
    /// G H I
    ///
    /// Operation: insertLeft, target=B (r0c1, index 1), source=D (index 3)
    /// Expected result:
    /// A D B
    /// C E F
    /// G H I
    func testInsertLeft_DIntoB() async {
        // Setup
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        // Start preview (required before applying operations)
        await gridState.startPreview()

        // Apply operation
        let targetCell = CellCoordinate(page: 0, row: 0, column: 1) // B's position
        let sourceIndex = 3 // D

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        // Verify
        let result = await itemNames(gridState.items)
        let expected = ["A", "D", "B", "C", "E", "F", "G", "H", "I"]

        XCTAssertEqual(result, expected, "Insert left D into B's position should produce: A D B / C E F / G H I")
    }

    // MARK: - Test 2: Insert Right (A into B's right side)

    /// 3x3 layout:
    /// A B C
    /// D E F
    /// G H I
    ///
    /// Operation: insertRight, target=B (r0c1, index 1), source=A (index 0)
    /// Expected result (with forward squeeze):
    /// B A C
    /// D E F
    /// G H I
    ///
    /// Note: When source (A) is removed, index 0 becomes empty.
    /// Insert right of B means inserting at index 2.
    /// Since there's an empty slot at index 0 (before target), B should squeeze forward.
    func testInsertRight_AIntoB() async {
        // Setup
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .app(makeApp("D")), .app(makeApp("E")), .app(makeApp("F")),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        // Apply operation
        let targetCell = CellCoordinate(page: 0, row: 0, column: 1) // B's position
        let sourceIndex = 0 // A

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        // Verify
        let result = await itemNames(gridState.items)
        let expected = ["B", "A", "C", "D", "E", "F", "G", "H", "I"]

        XCTAssertEqual(result, expected, "Insert right A into B's right side should produce: B A C / D E F / G H I (B squeezes forward)")
    }

    // MARK: - Test 3: Insert Left with Empty Slots

    /// 3x3 layout:
    /// A     B     C
    /// empty E     empty
    /// G     H     I
    ///
    /// Operation: insertLeft, target=E (r1c1, index 4), source=C (index 2)
    /// Expected result:
    /// A     B     empty
    /// empty C     E
    /// G     H     I
    func testInsertLeft_CIntoE_WithEmptySlots() async {
        // Setup
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .empty(UUID()), .app(makeApp("E")), .empty(UUID()),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        // Apply operation
        let targetCell = CellCoordinate(page: 0, row: 1, column: 1) // E's position (index 4)
        let sourceIndex = 2 // C

        await gridState.applyOperation(
            operation: .insertLeft,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        // Verify
        let result = await itemNames(gridState.items)
        let expected = ["A", "B", "empty", "empty", "C", "E", "G", "H", "I"]

        XCTAssertEqual(result, expected, "Insert left C into E's position should produce: A B empty / empty C E / G H I")
    }

    // MARK: - Test 4: Insert Right with Empty Slots

    /// 3x3 layout:
    /// A     B     C
    /// empty E     empty
    /// G     H     I
    ///
    /// Operation: insertRight, target=E (r1c1, index 4), source=C (index 2)
    /// Expected result:
    /// A     B     empty
    /// empty E     C
    /// G     H     I
    func testInsertRight_CIntoE_WithEmptySlots() async {
        // Setup
        let layout = make3x3Layout()
        let gridState = await GridState(items: [
            .app(makeApp("A")), .app(makeApp("B")), .app(makeApp("C")),
            .empty(UUID()), .app(makeApp("E")), .empty(UUID()),
            .app(makeApp("G")), .app(makeApp("H")), .app(makeApp("I"))
        ])

        await gridState.startPreview()

        // Apply operation
        let targetCell = CellCoordinate(page: 0, row: 1, column: 1) // E's position (index 4)
        let sourceIndex = 2 // C

        await gridState.applyOperation(
            operation: .insertRight,
            targetCell: targetCell,
            sourceIndex: sourceIndex,
            layout: layout
        )

        // Verify
        let result = await itemNames(gridState.items)
        let expected = ["A", "B", "empty", "empty", "E", "C", "G", "H", "I"]

        XCTAssertEqual(result, expected, "Insert right C into E's right side should produce: A B empty / empty E C / G H I")
    }
}
