import Testing
@testable import LauncherCore

@Test func testPinyin() async throws {
    let result = pinyin("你好")
    #expect(result == "nihao")
}
