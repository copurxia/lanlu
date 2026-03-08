# `image` 包替换 `vips_ffi` 迁移计划

## 目标与约束

- [ ] 新建一个纯自研的 `packages/image` 包，整体接口风格参考 `ref/image`
- [ ] 不引入 `image4cj` 作为依赖，`ref/image4cj` 只作为实现代码参考
- [ ] 尽可能使用仓颉实现图像能力，避免 FFI；只有在阶段性无法绕开时才单独评估最小化补充方案
- [ ] 最终支持格式范围以 `ref/image` 为目标
- [ ] 第一阶段先支持 `ref/image4cj` 已覆盖格式：`jpeg`、`png`、`gif`
- [ ] 第一阶段额外补充 `avif` 的读写或至少满足项目所需的 `avif` 编码输出能力
- [ ] 优先覆盖当前项目真实使用场景，不追求一次性完整复刻 `ref/image` 全部高级能力

## 能力边界分期

### 阶段一：可落地最小闭环

- [ ] 支持 `jpeg`、`png`、`gif` 解码
- [ ] 支持 `avif` 编码输出
- [ ] 打通 `DynamicImage -> RgbaImage -> imageops -> AvifEncoder`
- [ ] 覆盖当前项目需要的缩放、裁切、旋转、thumbhash、文本渲染链路

### 阶段二：向 `ref/image` 靠齐

- [ ] 梳理 `ref/image` 当前支持的全部格式和能力矩阵
- [ ] 制定剩余格式的增量实现顺序
- [ ] 逐步补齐更多编解码器与颜色模型
- [ ] 逐步补齐与 `ref/image` 对齐的 API 细节和错误模型

## 现状梳理

- [ ] 盘点 `src/shared/utils/vips_convert_utils.cj` 中现有对 `vips_ffi` 的能力封装
- [ ] 梳理 `src/shared/utils/archive_utils.cj` 对图片缩略图、头像、标签背景图的调用路径
- [ ] 梳理 `src/contexts/plugin/domain/plugin_cover_utils.cj` 对封面转换和 thumbhash 的依赖
- [ ] 明确哪些行为必须保持兼容：输出尺寸、裁切策略、AVIF 输出、thumbhash 结果、错误处理策略
- [ ] 识别当前哪些能力以前依赖 libvips 特性，迁移时需要纯仓颉重做

## 包结构设计

- [ ] 创建 `packages/image` 包
- [ ] 设计 `packages/image/src/lib.cj` 作为统一导出入口
- [ ] 设计核心模块目录：`core`、`io`、`imageops`、`codecs`、`ext`
- [ ] 约束对外 API 命名风格尽量贴近 `ref/image`
- [ ] 约束内部实现分层，避免业务代码直接依赖 codec 细节

## 核心数据模型

- [ ] 实现 `ImageError`，统一封装解码、编码、格式识别、参数错误
- [ ] 实现几何类型：`Size`、`Point`、`Rect`
- [ ] 实现像素容器：`ImageBuffer<TPixel>`
- [ ] 实现 `RgbaImage`
- [ ] 实现 `DynamicImage`
- [ ] 第一阶段只保证 RGBA8 工作流闭环
- [ ] 为后续扩展保留颜色模型与像素格式的演进空间

## I/O 分层

- [ ] 实现 `ImageFormat` 枚举或等价类型
- [ ] 第一阶段实现 `jpeg`、`png`、`gif`、`avif` 的格式识别
- [ ] 实现 `ImageReader.open(path)`
- [ ] 实现 `withGuessedFormat()` 或等价格式探测接口
- [ ] 实现 `decode()`，返回 `DynamicImage`
- [ ] 实现 `DynamicImage.toRgba8()`
- [ ] 实现 `writeTo(path, format)` 或等价输出接口
- [ ] 明确 `avif` 在第一阶段是“完整读写”还是“先只编码输出”的范围边界

## 编解码器实现策略

- [ ] `jpeg`：优先参考 `ref/image4cj` 的纯仓颉实现
- [ ] `png`：优先参考 `ref/image4cj` 的纯仓颉实现
- [ ] `gif`：优先参考 `ref/image4cj` 的纯仓颉实现
- [ ] `avif`：优先寻找纯仓颉可实现路径，若难度过高则先限定为项目必需最小能力
- [ ] 明确每个 codec 的输入输出像素格式与错误处理约定
- [ ] 保证 codec 层不泄漏到底层实现细节给业务层

## 图像操作能力

- [ ] 实现 `resize`
- [ ] 实现 `crop`
- [ ] 实现 `crop_imm` 或等价不可变裁切接口
- [ ] 实现 `resizeToFill`
- [ ] 实现 `thumbnail`
- [ ] 实现 `rotate90/180/270`
- [ ] 评估并实现 `autorotate` 能力，兼容当前 EXIF 自动旋转需求
- [ ] 优先复用纯仓颉像素操作逻辑，不依赖外部图像处理库

## 项目专用扩展

- [ ] 实现 `AvifEncoder.encode(image, outputPath)`
- [ ] 实现 `Thumbhash.fromRgba(image)`
- [ ] 实现文本渲染扩展 `TextRenderer`
- [ ] 为封面、头像、标签背景图抽出稳定的高层 helper，避免业务层直接拼接底层操作
- [ ] 重新定义当前 `VipsConvertUtils` 中与业务相关的高层入口，迁移到 `packages/image` 或配套 helper

## 实现策略

- [ ] 不沿用 `vips_ffi` 的架构作为长期方案
- [ ] 新 `image` 包优先从纯仓颉像素模型和 codec 开始搭建
- [ ] `image4cj` 只参考算法、数据结构和 codec 实现，不照搬其包结构和对外命名
- [ ] 第一阶段先完成项目必需能力闭环，再扩展到 `ref/image` 级别覆盖面
- [ ] 若 `avif` 纯仓颉实现难度显著高于预期，先将其单独列为受控例外并保持隔离设计

## 调用方迁移

- [ ] 将 `src/shared/utils/archive_utils.cj` 改为依赖新 `image` 包
- [ ] 将 `src/contexts/plugin/domain/plugin_cover_utils.cj` 改为依赖新 `image` 包
- [ ] 评估其他模块是否仍然直接或间接耦合 `VipsConvertUtils`
- [ ] 让业务代码只依赖 `image` 的高层 API，而不是具体 codec 或历史 FFI 细节

## 兼容与验证

- [ ] 为 `jpeg`、`png`、`gif` 解码分别补充最小验证用例
- [ ] 为 `avif` 输出补充最小验证用例
- [ ] 为缩略图生成补充最小验证用例：宽度缩放到 500，高度最大 1000，顶部裁切
- [ ] 为头像生成补充最小验证用例：256x256，cover + center crop
- [ ] 为标签背景图生成补充最小验证用例：固定宽度，顶部裁切高度
- [ ] 验证透明 PNG 转 AVIF 时 alpha 保留正常
- [ ] 验证 thumbhash 结果在迁移前后保持稳定或误差在可接受范围内
- [ ] 验证文本渲染输出尺寸、透明背景和像素格式符合预期
- [ ] 验证格式探测行为与 `ref/image` 设计目标一致

## 收尾工作

- [ ] 清理或缩减 `src/shared/utils/vips_convert_utils.cj` 的职责
- [ ] 删除 `module` 中对 `vips_ffi` 的直接业务依赖
- [ ] 清理仍然残留的图像 FFI 耦合点
- [ ] 更新相关开发文档，说明新 `image` 包的定位、接口、阶段能力与未完成边界

## 推荐实施顺序

- [ ] 第 1 步：定义 `packages/image` 的公共 API 和目录结构
- [ ] 第 2 步：先接入纯仓颉 `jpeg` / `png` / `gif` 解码链路
- [ ] 第 3 步：打通 `ImageReader -> DynamicImage -> RgbaImage` 最小链路
- [ ] 第 4 步：补齐 `resize` / `crop` / `resizeToFill` / `thumbnail`
- [ ] 第 5 步：完成 `avif` 输出能力
- [ ] 第 6 步：迁移 `archive_utils` 的缩略图、头像、标签背景图流程
- [ ] 第 7 步：迁移 `plugin_cover_utils`
- [ ] 第 8 步：补齐文本渲染与验证
- [ ] 第 9 步：下线旧 `VipsConvertUtils` 业务职责
- [ ] 第 10 步：继续补齐 `ref/image` 其余格式支持

## 第一阶段文件级拆分

### 包与入口

- [ ] 创建 `packages/image/cjpm.toml`
- [ ] 创建 `packages/image/src/lib.cj`
- [ ] 在 `lib.cj` 中统一导出 `core`、`io`、`imageops`、`codecs`、`ext`
- [ ] 在 `module` 依赖中预留 `image = { path = "packages/image" }` 的接入位置

### `core` 模块

- [ ] 创建 `packages/image/src/core/error.cj`
- [ ] 创建 `packages/image/src/core/geometry.cj`
- [ ] 创建 `packages/image/src/core/pixel.cj`
- [ ] 创建 `packages/image/src/core/image_buffer.cj`
- [ ] 创建 `packages/image/src/core/rgba_image.cj`
- [ ] 创建 `packages/image/src/core/dynamic_image.cj`
- [ ] 创建 `packages/image/src/core/mod.cj`

### `io` 模块

- [ ] 创建 `packages/image/src/io/image_format.cj`
- [ ] 创建 `packages/image/src/io/image_reader.cj`
- [ ] 创建 `packages/image/src/io/image_writer.cj`
- [ ] 创建 `packages/image/src/io/format_detection.cj`
- [ ] 创建 `packages/image/src/io/mod.cj`

### `imageops` 模块

- [ ] 创建 `packages/image/src/imageops/resize.cj`
- [ ] 创建 `packages/image/src/imageops/crop.cj`
- [ ] 创建 `packages/image/src/imageops/rotate.cj`
- [ ] 创建 `packages/image/src/imageops/thumbnail.cj`
- [ ] 创建 `packages/image/src/imageops/overlay.cj`
- [ ] 创建 `packages/image/src/imageops/mod.cj`

### `codecs` 模块

- [ ] 创建 `packages/image/src/codecs/jpeg/decoder.cj`
- [ ] 创建 `packages/image/src/codecs/png/decoder.cj`
- [ ] 创建 `packages/image/src/codecs/gif/decoder.cj`
- [ ] 创建 `packages/image/src/codecs/avif/encoder.cj`
- [ ] 视阶段一范围决定是否创建 `packages/image/src/codecs/avif/decoder.cj`
- [ ] 创建 `packages/image/src/codecs/mod.cj`

### `ext` 模块

- [ ] 创建 `packages/image/src/ext/thumbhash.cj`
- [ ] 创建 `packages/image/src/ext/text_renderer.cj`
- [ ] 创建 `packages/image/src/ext/project_presets.cj`
- [ ] 创建 `packages/image/src/ext/mod.cj`

## 第一阶段类型设计

### `core/error.cj`

- [ ] 定义 `ImageError` 基础类型
- [ ] 定义错误分类：`UnknownFormat`、`DecodeFailed`、`EncodeFailed`、`InvalidDimensions`、`UnsupportedFeature`、`IoError`
- [ ] 统一错误构造和字符串化输出，便于替换现有 `ProcessResultData.error`

### `core/geometry.cj`

- [ ] 定义 `Size { width, height }`
- [ ] 定义 `Point { x, y }`
- [ ] 定义 `Rect { x, y, width, height }`
- [ ] 提供 `right()`、`bottom()`、`contains()`、`intersect()` 等基础方法
- [ ] 提供面向裁切和缩放的辅助函数，避免业务层重复写坐标逻辑

### `core/pixel.cj`

- [ ] 定义 `Rgba8 { r, g, b, a }`
- [ ] 约束第一阶段内部统一使用 RGBA8 作为中间表示
- [ ] 预留后续扩展到灰度、RGB8、RGBA16 的接口位点，但第一阶段不实现复杂像素族

### `core/image_buffer.cj`

- [ ] 定义 `ImageBuffer<TPixel>` 或等价专用容器
- [ ] 统一保存 `width`、`height`、`stride`、`pixels`
- [ ] 提供 `getPixel()`、`setPixel()`、`subImage()`、`clone()` 等基础能力
- [ ] 明确边界访问策略，避免静默越界

### `core/rgba_image.cj`

- [ ] 定义 `RgbaImage` 作为 `ImageBuffer<Rgba8>` 的高频特化类型
- [ ] 提供 `fromRaw(width, height, bytes)`
- [ ] 提供 `intoRawBytes()`
- [ ] 提供 `cropView()` 或等价能力

### `core/dynamic_image.cj`

- [ ] 定义 `DynamicImage`，第一阶段至少包含 `Rgba8` 变体
- [ ] 提供 `width()`、`height()`、`colorType()`、`toRgba8()`
- [ ] 提供 `writeTo(path, format)` 代理到 `io/image_writer.cj`
- [ ] 保持对外风格接近 `ref/image` 的动态图像模型

## 第一阶段 I/O API 草图

### `io/image_format.cj`

- [ ] 定义 `ImageFormat`：`Jpeg`、`Png`、`Gif`、`Avif`
- [ ] 提供 `fromExtension(ext)`
- [ ] 提供 `fromMagic(bytes)`
- [ ] 明确未知格式返回方式

### `io/format_detection.cj`

- [ ] 实现按 magic number 探测 `jpeg`、`png`、`gif`、`avif`
- [ ] 实现按扩展名兜底探测
- [ ] 约束探测顺序和冲突处理方式

### `io/image_reader.cj`

- [ ] 设计 `ImageReader.open(path)`
- [ ] 设计 `withFormat(format)`
- [ ] 设计 `withGuessedFormat()`
- [ ] 设计 `decode(): DynamicImage`
- [ ] 设计 `intoDimensions()` 或 `decodeConfig()`，用于只读取宽高和格式

### `io/image_writer.cj`

- [ ] 设计 `write(image, path, format)`
- [ ] 第一阶段至少实现 `Avif` 输出
- [ ] 评估是否同步提供 `Png`/`Jpeg` 输出，以方便调试和测试

## 第一阶段 `imageops` API 草图

### `imageops/resize.cj`

- [ ] 实现 `resize(image, width, height, filter)`
- [ ] 第一阶段先提供 `Nearest` 与 `Triangle` 或项目足够用的最小 filter 集
- [ ] 约束宽高为 0 或负数时的错误行为

### `imageops/crop.cj`

- [ ] 实现 `crop(image, rect)`
- [ ] 实现 `cropImm(image, rect)`
- [ ] 明确超出边界时是裁到交集还是报错

### `imageops/rotate.cj`

- [ ] 实现 `rotate90(image)`
- [ ] 实现 `rotate180(image)`
- [ ] 实现 `rotate270(image)`
- [ ] 评估 `autorotate` 是否单独放在 `ext` 或 `io` 层

### `imageops/thumbnail.cj`

- [ ] 实现 `thumbnail(image, width, maxHeight)`
- [ ] 实现 `resizeToFill(image, width, height, anchor)`
- [ ] 提供 `Top`, `Center` 等裁切锚点，满足当前缩略图和头像场景

### `imageops/overlay.cj`

- [ ] 实现最小 `overlay(dst, src, x, y)`
- [ ] 为文本渲染与未来水印功能预留能力

## 第一阶段 codec 细化

### `jpeg`

- [ ] 参考 `ref/image4cj/src/jpeg/*.cj` 迁移解码核心思路
- [ ] 抽离出只属于新 `image` 包的错误与像素输出结构
- [ ] 明确输出统一转为 `DynamicImage::Rgba8`

### `png`

- [ ] 参考 `ref/image4cj/src/png/*.cj` 与 `src/png/zlib/*.cj`
- [ ] 先支持项目最常见的 PNG 颜色类型
- [ ] 明确透明通道处理策略，保证后续 AVIF 编码正确保留 alpha

### `gif`

- [ ] 参考 `ref/image4cj/src/gif/*.cj`
- [ ] 第一阶段先支持静态首帧解码，或明确是否需要动画支持
- [ ] 若只做首帧，需在 API 文档中清楚标注

### `avif`

- [ ] 先定义 `AvifEncoder` 抽象接口，避免业务层依赖具体实现
- [ ] 评估纯仓颉实现成本：容器、色彩、压缩链路、alpha 支持、性能
- [ ] 若首版仅实现编码输出，需在 `todo` 中明确“读取延后”
- [ ] 保证 `RgbaImage -> AVIF` 在透明图和普通封面图上都可用

## 项目专用高层 API 草图

### `ext/project_presets.cj`

- [ ] 实现 `createArchiveThumbnail(inputPath, outputPath)`
- [ ] 实现 `createArchiveThumbnailWithThumbhash(inputPath, outputPath)`
- [ ] 实现 `createAvatar(inputPath, outputPath)`
- [ ] 实现 `createAvatarWithThumbhash(inputPath, outputPath)`
- [ ] 实现 `createTagBackground(inputPath, outputPath)`
- [ ] 实现 `createTagBackgroundWithThumbhash(inputPath, outputPath)`
- [ ] 这些 helper 内部只依赖 `ImageReader`、`imageops`、`AvifEncoder`、`Thumbhash`

### `ext/thumbhash.cj`

- [ ] 将现有 thumbhash 算法适配到 `RgbaImage`
- [ ] 保证不需要重新解码写出的 AVIF 再生成 hash

### `ext/text_renderer.cj`

- [ ] 明确文本渲染是否要求纯仓颉实现
- [ ] 若纯仓颉文本栈成本过高，单独列出风险并延后，不阻塞图片包主体落地
- [ ] 在接口层先固定 `render(text, width, height, options): RgbaImage`

## 业务迁移分解

### `src/shared/utils/archive_utils.cj`

- [ ] 用 `packages/image/src/ext/project_presets.cj` 替换现有缩略图生成调用
- [ ] 移除对 `VipsConvertUtils.tryConvertToAvifThumbnail*` 的依赖
- [ ] 保持现有输出尺寸与裁切策略不变

### `src/contexts/plugin/domain/plugin_cover_utils.cj`

- [ ] 用新 `createArchiveThumbnailWithThumbhash` 或更贴合插件封面的 helper 替换旧逻辑
- [ ] 保持当前资产落库和文件替换流程不变，只替换图像处理实现

## 风险与决策点

- [ ] 决策：`avif` 第一阶段是否只编码不解码
- [ ] 决策：`gif` 第一阶段是否只支持首帧
- [ ] 决策：文本渲染是否允许暂时滞后于图像包主体
- [ ] 决策：`autorotate` 是否第一阶段必须完成
- [ ] 风险：纯仓颉 `avif` 编码复杂度可能显著高于 `jpeg/png/gif`
- [ ] 风险：若缺少 `ref/image` 对应测试素材，需要补一组本地样本图

## 第一阶段里程碑

- [ ] 里程碑 A：完成 `core` + `io` 基础骨架并可识别格式
- [ ] 里程碑 B：完成 `jpeg/png/gif` 解码并输出 `DynamicImage`
- [ ] 里程碑 C：完成 `resize/crop/thumbnail/rotate`
- [ ] 里程碑 D：完成 `avif` 输出与 `thumbhash`
- [ ] 里程碑 E：完成 `archive_utils` 与 `plugin_cover_utils` 迁移
- [ ] 里程碑 F：移除图像主链路对 `vips_ffi` 的依赖

## 第一阶段接口签名草案

> 目标：先固定对外 API 形状，再逐步填充纯仓颉实现；命名尽量向 `ref/image` 靠拢，但保留适合当前项目的最小闭环。

### `packages/image/src/lib.cj`

- [ ] 导出建议：
- [ ] `public import image.core.*`
- [ ] `public import image.io.*`
- [ ] `public import image.imageops.*`
- [ ] `public import image.codecs.*`
- [ ] `public import image.ext.*`

### `packages/image/src/core/error.cj`

- [ ] 接口草案：
- [ ] `public enum ImageErrorKind { UnknownFormat | DecodeFailed | EncodeFailed | InvalidDimensions | UnsupportedFeature | IoError }`
- [ ] `public class ImageError <: ToString { kind: ImageErrorKind, message: String }`
- [ ] `public func toString(): String`
- [ ] `public static func unknownFormat(message!: String = "unknown image format"): ImageError`
- [ ] `public static func decodeFailed(message: String): ImageError`
- [ ] `public static func encodeFailed(message: String): ImageError`
- [ ] `public static func invalidDimensions(message: String): ImageError`
- [ ] `public static func unsupportedFeature(message: String): ImageError`
- [ ] `public static func ioError(message: String): ImageError`

### `packages/image/src/core/geometry.cj`

- [ ] 接口草案：
- [ ] `public class Size { public let width: Int64; public let height: Int64 }`
- [ ] `public class Point { public let x: Int64; public let y: Int64 }`
- [ ] `public class Rect { public let x: Int64; public let y: Int64; public let width: Int64; public let height: Int64 }`
- [ ] `public func right(): Int64`
- [ ] `public func bottom(): Int64`
- [ ] `public func contains(point: Point): Bool`
- [ ] `public func intersect(other: Rect): Rect`
- [ ] `public func isEmpty(): Bool`

### `packages/image/src/core/pixel.cj`

- [ ] 接口草案：
- [ ] `public class Rgba8 { public var r: UInt8; public var g: UInt8; public var b: UInt8; public var a: UInt8 }`
- [ ] `public init(r!: UInt8 = 0, g!: UInt8 = 0, b!: UInt8 = 0, a!: UInt8 = 255)`
- [ ] `public static func transparent(): Rgba8`
- [ ] `public static func opaqueBlack(): Rgba8`
- [ ] `public static func opaqueWhite(): Rgba8`

### `packages/image/src/core/image_buffer.cj`

- [ ] 接口草案：
- [ ] `public class ImageBuffer<TPixel> {`
- [ ] `  public let width: Int64`
- [ ] `  public let height: Int64`
- [ ] `  public let stride: Int64`
- [ ] `  public var pixels: Array<TPixel>`
- [ ] `}`
- [ ] `public init(width: Int64, height: Int64, stride!: Int64 = 0, pixels!: Array<TPixel> = [])`
- [ ] `public func len(): Int64`
- [ ] `public func isEmpty(): Bool`
- [ ] `public func getPixel(x: Int64, y: Int64): TPixel`
- [ ] `public func setPixel(x: Int64, y: Int64, pixel: TPixel): Unit`
- [ ] `public func clone(): ImageBuffer<TPixel>`

### `packages/image/src/core/rgba_image.cj`

- [ ] 接口草案：
- [ ] `public class RgbaImage <: ImageBuffer<Rgba8> {`
- [ ] `  public init(width: Int64, height: Int64)`
- [ ] `  public init(width: Int64, height: Int64, pixels: Array<Rgba8>)`
- [ ] `  public static func fromRaw(width: Int64, height: Int64, bytes: Array<UInt8>): RgbaImage`
- [ ] `  public func intoRawBytes(): Array<UInt8>`
- [ ] `  public func dimensions(): Size`
- [ ] `  public func cropView(rect: Rect): RgbaImage`
- [ ] `}`

### `packages/image/src/core/dynamic_image.cj`

- [ ] 接口草案：
- [ ] `public enum ColorType { Rgba8 }`
- [ ] `public enum DynamicImage { Rgba8Image(RgbaImage) }`
- [ ] `public func width(): Int64`
- [ ] `public func height(): Int64`
- [ ] `public func dimensions(): Size`
- [ ] `public func colorType(): ColorType`
- [ ] `public func toRgba8(): RgbaImage`
- [ ] `public func writeTo(path: String, format: ImageFormat): Unit`

### `packages/image/src/io/image_format.cj`

- [ ] 接口草案：
- [ ] `public enum ImageFormat { Jpeg | Png | Gif | Avif }`
- [ ] `public func extension(): String`
- [ ] `public func mimeType(): String`
- [ ] `public static func fromExtension(ext: String): ?ImageFormat`
- [ ] `public static func fromPath(path: String): ?ImageFormat`

### `packages/image/src/io/format_detection.cj`

- [ ] 接口草案：
- [ ] `public func guessFormatFromMagic(header: Array<UInt8>): ?ImageFormat`
- [ ] `public func guessFormatFromPath(path: String): ?ImageFormat`
- [ ] `public func guessFormat(path: String, header: Array<UInt8>): ?ImageFormat`

### `packages/image/src/io/image_reader.cj`

- [ ] 接口草案：
- [ ] `public class ImageReader {`
- [ ] `  public static func open(path: String): ImageReader`
- [ ] `  public func withFormat(format: ImageFormat): ImageReader`
- [ ] `  public func withGuessedFormat(): ImageReader`
- [ ] `  public func decode(): DynamicImage`
- [ ] `  public func decodeConfig(): ImageConfig`
- [ ] `}`
- [ ] `public class ImageConfig { public let width: Int64; public let height: Int64; public let format: ?ImageFormat; public let colorType: ?ColorType }`

### `packages/image/src/io/image_writer.cj`

- [ ] 接口草案：
- [ ] `public class ImageWriter {`
- [ ] `  public static func write(image: DynamicImage, path: String, format: ImageFormat): Unit`
- [ ] `}`
- [ ] `public func saveBufferAsPng(image: RgbaImage, path: String): Unit`
- [ ] `public func saveBufferAsJpeg(image: RgbaImage, path: String, quality!: Int64 = 90): Unit`
- [ ] `public func saveBufferAsAvif(image: RgbaImage, path: String, quality!: Int64 = 75): Unit`

### `packages/image/src/imageops/resize.cj`

- [ ] 接口草案：
- [ ] `public enum FilterType { Nearest | Triangle }`
- [ ] `public func resize(image: DynamicImage, width: Int64, height: Int64, filter!: FilterType = FilterType.Triangle): DynamicImage`
- [ ] `public func resizeRgba(image: RgbaImage, width: Int64, height: Int64, filter!: FilterType = FilterType.Triangle): RgbaImage`

### `packages/image/src/imageops/crop.cj`

- [ ] 接口草案：
- [ ] `public func crop(image: DynamicImage, rect: Rect): DynamicImage`
- [ ] `public func cropImm(image: DynamicImage, rect: Rect): DynamicImage`
- [ ] `public func cropRgba(image: RgbaImage, rect: Rect): RgbaImage`

### `packages/image/src/imageops/rotate.cj`

- [ ] 接口草案：
- [ ] `public func rotate90(image: DynamicImage): DynamicImage`
- [ ] `public func rotate180(image: DynamicImage): DynamicImage`
- [ ] `public func rotate270(image: DynamicImage): DynamicImage`
- [ ] `public func rotate90Rgba(image: RgbaImage): RgbaImage`
- [ ] `public func rotate180Rgba(image: RgbaImage): RgbaImage`
- [ ] `public func rotate270Rgba(image: RgbaImage): RgbaImage`

### `packages/image/src/imageops/thumbnail.cj`

- [ ] 接口草案：
- [ ] `public enum CropAnchor { Top | Center }`
- [ ] `public func thumbnail(image: DynamicImage, width: Int64, maxHeight: Int64, anchor!: CropAnchor = CropAnchor.Top): DynamicImage`
- [ ] `public func resizeToFill(image: DynamicImage, width: Int64, height: Int64, anchor!: CropAnchor = CropAnchor.Center): DynamicImage`
- [ ] `public func thumbnailRgba(image: RgbaImage, width: Int64, maxHeight: Int64, anchor!: CropAnchor = CropAnchor.Top): RgbaImage`
- [ ] `public func resizeToFillRgba(image: RgbaImage, width: Int64, height: Int64, anchor!: CropAnchor = CropAnchor.Center): RgbaImage`

### `packages/image/src/imageops/overlay.cj`

- [ ] 接口草案：
- [ ] `public func overlay(dst: RgbaImage, src: RgbaImage, x: Int64, y: Int64): RgbaImage`
- [ ] `public func overlayInPlace(dst: RgbaImage, src: RgbaImage, x: Int64, y: Int64): Unit`

### `packages/image/src/codecs/jpeg/decoder.cj`

- [ ] 接口草案：
- [ ] `public class JpegDecoder {`
- [ ] `  public static func decode(path: String): DynamicImage`
- [ ] `  public static func decodeConfig(path: String): ImageConfig`
- [ ] `}`

### `packages/image/src/codecs/png/decoder.cj`

- [ ] 接口草案：
- [ ] `public class PngDecoder {`
- [ ] `  public static func decode(path: String): DynamicImage`
- [ ] `  public static func decodeConfig(path: String): ImageConfig`
- [ ] `}`

### `packages/image/src/codecs/gif/decoder.cj`

- [ ] 接口草案：
- [ ] `public class GifDecoder {`
- [ ] `  public static func decode(path: String): DynamicImage`
- [ ] `  public static func decodeConfig(path: String): ImageConfig`
- [ ] `  public static func decodeFirstFrame(path: String): DynamicImage`
- [ ] `}`

### `packages/image/src/codecs/avif/encoder.cj`

- [ ] 接口草案：
- [ ] `public class AvifEncodeOptions {`
- [ ] `  public var quality: Int64 = 75`
- [ ] `  public var speed: Int64 = 6`
- [ ] `  public var preserveAlpha: Bool = true`
- [ ] `}`
- [ ] `public class AvifEncoder {`
- [ ] `  public static func encode(image: DynamicImage, outputPath: String, options!: ?AvifEncodeOptions = None): Unit`
- [ ] `  public static func encodeRgba(image: RgbaImage, outputPath: String, options!: ?AvifEncodeOptions = None): Unit`
- [ ] `}`

### `packages/image/src/ext/thumbhash.cj`

- [ ] 接口草案：
- [ ] `public class Thumbhash {`
- [ ] `  public static func fromImage(image: DynamicImage): String`
- [ ] `  public static func fromRgba(image: RgbaImage): String`
- [ ] `}`

### `packages/image/src/ext/text_renderer.cj`

- [ ] 接口草案：
- [ ] `public class TextRenderOptions {`
- [ ] `  public var width: Int64 = 0`
- [ ] `  public var height: Int64 = 0`
- [ ] `  public var fontSize: Int64 = 16`
- [ ] `  public var lineSpacing: Int64 = 0`
- [ ] `  public var color: Rgba8 = Rgba8.opaqueWhite()`
- [ ] `  public var background: Rgba8 = Rgba8.transparent()`
- [ ] `}`
- [ ] `public class TextRenderer {`
- [ ] `  public static func render(text: String, options!: ?TextRenderOptions = None): RgbaImage`
- [ ] `}`

### `packages/image/src/ext/project_presets.cj`

- [ ] 接口草案：
- [ ] `public class ProcessResultData { public var success: Bool; public var outputPath: String; public var error: String }`
- [ ] `public class ProjectImagePresets {`
- [ ] `  public static func createArchiveThumbnail(inputPath: String, outputPath: String): ProcessResultData`
- [ ] `  public static func createArchiveThumbnailWithThumbhash(inputPath: String, outputPath: String): (ProcessResultData, String)`
- [ ] `  public static func createAvatar(inputPath: String, outputPath: String): ProcessResultData`
- [ ] `  public static func createAvatarWithThumbhash(inputPath: String, outputPath: String): (ProcessResultData, String)`
- [ ] `  public static func createTagBackground(inputPath: String, outputPath: String): ProcessResultData`
- [ ] `  public static func createTagBackgroundWithThumbhash(inputPath: String, outputPath: String): (ProcessResultData, String)`
- [ ] `}`

## 第一阶段实现顺序再细化

- [ ] 任务 1：先写 `core/error.cj`、`core/geometry.cj`、`core/pixel.cj`
- [ ] 任务 2：再写 `core/image_buffer.cj`、`core/rgba_image.cj`、`core/dynamic_image.cj`
- [ ] 任务 3：实现 `io/image_format.cj`、`io/format_detection.cj`、`io/image_reader.cj`
- [ ] 任务 4：先接 `jpeg/png/gif` 解码器壳子，保证 `decode()` 能分发
- [ ] 任务 5：实现 `imageops/resize.cj`、`crop.cj`、`rotate.cj`、`thumbnail.cj`
- [ ] 任务 6：实现 `ext/thumbhash.cj`
- [ ] 任务 7：实现 `codecs/avif/encoder.cj`
- [ ] 任务 8：实现 `ext/project_presets.cj`
- [ ] 任务 9：迁移 `archive_utils`
- [ ] 任务 10：迁移 `plugin_cover_utils`
- [ ] 任务 11：最后再评估 `text_renderer.cj` 的落地路径

## 第一阶段建议先不做的内容

- [ ] 暂不实现复杂颜色模型族
- [ ] 暂不实现完整动画 GIF 工作流，除非业务确认必须
- [ ] 暂不实现完整 AVIF 解码，除非业务链路明确需要
- [ ] 暂不追求和 `ref/image` 完全一致的泛型 trait 体系
- [ ] 暂不处理所有 EXIF 元数据，只优先解决方向旋转所需最小信息
