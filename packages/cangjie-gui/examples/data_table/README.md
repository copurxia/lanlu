# data_table：数据表格

一张服务器机群监控表，集中演示 `Table` 控件：多列、固定表头、窗口化滚动、点击列头排序、
行选择跟随数据、自定义单元格（CPU 负载条），以及选中行驱动的详情栏，是后台最常见的
数据网格场景。

## 演示要点

- `Table(id, columns, rows, selected)` 的用法：`TableColumn(title, width, numeric)` 定义列，
  `Array<Array<String>>` 提供按列索引的单元格数据
- 数值列（`numeric: true`）右对齐并按数值排序，而非字典序（`88 < 100`，而不是 `"100" < "88"`）
- 自定义单元格（`TableColumn.cell`）：CPU 列画负载条与数值，排序仍按字符串数值，显示与排序键解耦
- 点击列头排序、再次点击反向；排序在显示层进行，选择以原始行索引存储，因此排序后高亮仍跟随同一行
- 键盘可达：`Tab` 聚焦表格后 `↑/↓/Home/End` 移动选择并把选中行滚入视区
- 选中行详情由 `State.map` 派生，编辑选择即实时刷新

## 文件结构

| 文件 | 职责 |
|---|---|
| [main.cj](src/main.cj) | 入口：模型、窗口与最小尺寸 |
| [data.cj](src/data.cj) | 列定义、种子服务器行、选中行摘要文本 |
| [model.cj](src/model.cj) | `FleetModel`：行数据、选中索引、派生详情 |
| [views.cj](src/views.cj) | 标题、填满空间的 `Table`、详情栏 |
| [theme.cj](src/theme.cj) | 浅色监控台主题与字号令牌 |

## 关键实现

### 一行代码接入数据表格

`Table` 自带表头、滚动、排序与键盘导航；应用只需给出列定义与字符串行：

```cangjie
Table("fleet.table", serverColumns(), model.rows, model.selected).flex()
```

列定义声明宽度与是否数值列，数值列自动右对齐、按数值排序：

```cangjie
TableColumn("主机名", 180.0)
TableColumn("连接数", 120.0, numeric: true)
```

### 自定义单元格：显示与排序解耦

“CPU %”列用 `cell` 回调接管绘制：迷你负载条按百分比填充、负载越高颜色越警示，右侧保留数值。
单元格字符串仍是 `"23"`，`numeric` 排序照常；表格先画好行底与选中高亮、把回调裁剪在单元格内，
回调只画内容、不接收事件（行点击照常选中）：

```cangjie
TableColumn("CPU %", 100.0, numeric: true, cell: cpuCellPainter)

func cpuCellPainter(ctx: UiContext, _: Int64, value: String, cell: Rect): Unit {
    // 轨道 + 按 value 百分比填充的负载条 + 右对齐数值文本
}
```

### 选择跟随数据行，而非屏幕位置

`Table` 把选择存为原始行索引。点击列头排序只改变显示顺序，选中行的高亮仍落在同一台服务器上；
键盘上下键在当前显示顺序中移动，因此排序后方向键仍然符合直觉。

### 详情栏由选择派生

底部摘要不复制数据，而是从选中索引 `map` 派生，选择变化即刷新：

```cangjie
this.summary = this.selected.map<String>({index => serverSummary(data, index)})
```

## 运行

```powershell
cd examples/data_table
cjpm run
```

点击任意列头排序（再次点击反向），点击行或 `Tab` 聚焦后用方向键选择。支持视觉回归快照：

```powershell
cjpm run --run-args "--snapshot data_table.bmp"
```
