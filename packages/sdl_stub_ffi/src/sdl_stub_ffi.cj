package sdl_stub_ffi

// 本包没有真正的功能代码：它存在的唯一目的是让 lgui 在「cjpm test」时把
// -lSDL3/-lSDL3_ttf 透传进测试可执行文件的链接行（静态依赖包的 link-option 会上浮，
// 与 packages/vips_ffi 的同款机制）。桩库由 tools/verify-cui-interactions.sh 生成。
// lgui 需引用下面的标记常量，否则 cjpm 会把"未使用的依赖"从链接行剪掉。
public let SDL_STUB_LINK_MARKER: UInt8 = 0
