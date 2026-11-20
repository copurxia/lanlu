package cui.media

import lbase.{Size}
import cui.base.{Renderer}
import cui.core.{LengthUnits, Theme, UiContext}

@Test
func imageViewMeasuresAndClosesWithoutLoadingTexture(): Unit {
    let ctx = UiContext(Renderer.headless(), Theme.light())
    let image = ImageView("missing.bmp", preferredHeight: 96.vp)

    let measured = image.measure(ctx, Size(240.0, 40.0))
    image.close()
    image.close()

    @Expect(measured.w, Float32(240.0))
    @Expect(measured.h, Float32(40.0))
    @Expect(image.isClosed())
}
