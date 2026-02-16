## Design

我写的 design 可能比较乱，算法也都当做伪代码。先分析 design，然后列出 todos，再根据 todos 一项项完成。

TODO:
[x] 1. 基础数据结构 (GridPosition, SlotContent, GridSlot, Page)
[x] 2. DropIntent 枚举
[x] 3. calculateIntent() 算法实现
[x] 4. Page 的 insertAndPush / removeAndCompact 方法
[x] 5. GridContainer 协议 + ContainerRules + GridLayout
[x] 6. RootContainer / FolderContainer 实现
[x] 7. 跨页溢出处理逻辑
[x] 8. Preview/Stable 双层模型
[x] 9. 文件夹拖出 transfer 逻辑

底层数据结构：

```
struct GridPosition: Hashable {
    let row: Int
    let column: Int
}

enum SlotContent {
    case empty
    case app(AppItem)
    case folder(FolderItem)
}

struct GridSlot {
    let position: GridPosition
    var content: SlotContent
}
struct Page {
    let rows: Int
    let columns: Int
    var slots: [[GridSlot]]   // 👈 二维数组
}
```

线性顺序（行优先）
```
func linearPositions() -> [GridPosition] {
    var result: [GridPosition] = []
    for r in 0..<rows {
        for c in 0..<columns {
            result.append(GridPosition(row: r, column: c))
        }
    }
    return result
}
```

拖动的命中测试：
先算在哪个 frame
```
func hitTestPosition(location: CGPoint) -> GridPosition {
    let col = Int(location.x / cellWidth)
    let row = Int(location.y / cellHeight)
    return GridPosition(row: row, column: col)
}
```
拿到 frame
```
func frame(for position: GridPosition) -> CGRect {
    CGRect(
        x: CGFloat(position.column) * cellWidth,
        y: CGFloat(position.row) * cellHeight,
        width: cellWidth,
        height: cellHeight
    )
}
```
拿到对应的 icon 的 frame:
```
struct IconLayout {
    let iconSize: CGSize
    let iconFrameInSlot: CGRect
}
```
dropIntent:
```
enum DropIntent {
    case intoEmpty(position: GridPosition)
    case insertBefore(target: GridPosition)
    case insertAfter(target: GridPosition)
    case merge(target: GridPosition)
}
```
merge行为：

氛围左和右和左右角落，上，下以及 icon 内的情况
```
extension Page {
    func calculateIntent(
        at localPoint: CGPoint, // 鼠标在当前 Slot 内的相对坐标 (0,0) 是左上角
        in slot: GridSlot,
        slotSize: CGSize,
        iconSize: CGSize
    ) -> DropIntent {
        
        // 1. 如果格子是空的，直接占用
        if case .empty = slot.content {
            return .intoEmpty(position: slot.position)
        }
        
        // 计算 Icon 在格子内的 Rect (居中对齐)
        let iconRect = CGRect(
            x: (slotSize.width - iconSize.width) / 2,
            y: (slotSize.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        
        // 2. 判定是否在 Icon 区域内 -> 触发合并
        if iconRect.contains(localPoint) {
            return .merge(target: slot.position)
        }
        
        // 3. 判定上下区域 -> 不触发判定 (假设返回空，或者维持之前的逻辑)
        // 你提到：上方下方区域不触发判定
        if localPoint.y < iconRect.minY || localPoint.y > iconRect.maxY {
            // 这里判断是否在“左右角落”
            if localPoint.x < iconRect.minX {
                return .insertBefore(target: slot.position)
            } else if localPoint.x > iconRect.maxX {
                return .insertAfter(target: slot.position)
            } else {
                // 正上方或正下方，不操作
                return .intoEmpty(position: slot.position) 
            }
        }
        
        // 4. 判定左右边缘
        if localPoint.x < iconRect.minX {
            return .insertBefore(target: slot.position)
        } else {
            return .insertAfter(target: slot.position)
        }
    }
}
```

关键点：防止“循环碰撞”
有一个细节你需要注意：被拖拽的那个图标（C）原本就在网格里。

在执行 insertWithPush 之前，你必须先将 C 从原来的位置删掉，变成 .empty。否则，当 A 和 B 往后移的时候，如果位移路径经过了 C 原本的位置，就会产生逻辑混乱。

page 内插入：
```
func insertAndReturnOverflow(
    _ item: LauncherNode
) -> LauncherNode? {

    var overflow: LauncherNode? = item

    for i in 0..<slots.count {
        swap(&slots[i].content, &overflow)
        if overflow == nil {
            return nil
        }
    }

    return overflow
}
```

如果跨页：
```
var carryingItem = draggedItem
var pageIndex = targetPage

while true {
    let overflow = pages[pageIndex]
        .insertAndReturnOverflow(carryingItem)

    if overflow == nil {
        break
    } else {
        carryingItem = overflow!
        pageIndex += 1

        if pageIndex == pages.count {
            pages.append(Page.empty())
        }
    }
}
```

UI 绑定的 page 其实有两层，一层 stable 一层 preview，每次拖动的时候是 preview，松手后如果位置合法，才更新 stable 模型。
```
previewPages = simulateDrop(
    base: stablePages,
    draggingItem: draggedItem,
    targetPage: pageIndex,
    targetSlot: slotIndex
)
```
UI绑定 pagesToRender = previewPages ?? stablePages
drop 成功的话：
`stablePages = previewPages
previewPages = nil`
drop取消：
`previewPages = nil `


文件夹内部 App 拖拽逻辑完全一致，除了不能嵌套文件夹。因此有如下设计：
```
protocol GridContainer {
    var pages: [Page] { get set }
    var layout: GridLayout { get }
    var rules: ContainerRules { get }
}
```
launcher:
```
struct RootContainer: GridContainer {
    var pages: [Page]
    let layout: GridLayout
    let rules = ContainerRules(
        allowsFolder: true
    )
}
```
folder container:
```
struct FolderContainer: GridContainer {
    let folderId: UUID
    var pages: [Page]
    let layout: GridLayout
    let rules = ContainerRules(
        allowsFolder: false   // 👈 禁止嵌套
    )
}
```
拖拽合并文件夹的逻辑：
```
func canMerge(
    dragged: LauncherNode,
    target: LauncherNode,
    in container: GridContainer
) -> Bool {
    guard container.rules.allowsFolder else { return false }
    return true
}
```

如果拖出文件夹：
```
if dragLocation outside folderBounds {
    transfer(
        from: FolderContainer,
        to: RootContainer
    )
}
```

