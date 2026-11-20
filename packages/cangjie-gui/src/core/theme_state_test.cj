package cui.core

@Test
public class ThemeStateTest {
    @TestCase
    func overlayTokensHaveDefaults() {
        let d = Theme.dark()
        let l = Theme.light()
        // 暗色：舞台黑、叠层文字浅；亮色：舞台浅、叠层文字深；恒深媒体文字两主题一致
        @Assert(d.stageBg != l.stageBg)
        @Assert(d.onOverlay != l.onOverlay)
        @Assert(d.onMedia == l.onMedia)
        @Assert(d.onMediaDim == l.onMediaDim)
    }

    @TestCase
    func defaultConstructorKeepsOverlayDefaults() {
        // 现有调用方（位置参数 + 命名参数）不传新字段也能编译且有值
        let t = Theme.dark()
        @Assert(t.overlaySurface.a > 0u8 || t.overlaySurface.r > 0u8)
    }
}
