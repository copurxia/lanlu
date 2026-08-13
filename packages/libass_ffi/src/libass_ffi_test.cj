package libass_ffi

import std.collection.ArrayList

@Test
func libassRuntimeMatchesCompiledMajor(): Unit {
    ensureCompatibleLibassRuntime()
    let (runtime, compiled) = libassVersions()
    @Expect(runtime >> 24, compiled >> 24)
}

@Test
func escapesPlainTextForAssChunks(): Unit {
    @Expect(escapeAssText("one\\two{tag}\nnext"), "one\\\\two\\{tag\\}\\Nnext")
    @Expect(escapeAssText("<b>bold</b> <i>italic</i> <u>under</u>"),
        "{\\b1}bold{\\b0} {\\i1}italic{\\i0} {\\u1}under{\\u0}")
}

@Test
func rendersPlainSubtitleIntoTransparentRgba(): Unit {
    let renderer = AssRenderer(320, 180)
    try {
        let events = ArrayList<PlainSubtitleEvent>()
        events.add(PlainSubtitleEvent(500, 1500, "Hello subtitle"))
        let track = renderer.newPlainTrack(events)
        let empty = renderer.render(0, [track])
        @Expect(empty.canvasWidth, 320)
        @Expect(empty.canvasHeight, 180)
        @Expect(empty.width, 0)
        @Expect(empty.height, 0)
        @Expect(nonTransparentPixels(empty), 0)
        let visible = renderer.render(1000, [track])
        @Expect(visible.canvasWidth, 320)
        @Expect(visible.canvasHeight, 180)
        @Expect(visible.width > 0 && visible.width < visible.canvasWidth)
        @Expect(visible.height > 0 && visible.height < visible.canvasHeight)
        @Expect(nonTransparentPixels(visible) > 0)
        let unchanged = renderer.render(1000, [track])
        @Expect(unchanged.changed, 0)
        @Expect(unchanged.rgba.size, 0)
    } finally {
        renderer.close()
    }
    @Expect(renderer.isClosed())
}

@Test
func readsStyledAssAndHonoursTopAlignment(): Unit {
    let renderer = AssRenderer(320, 180)
    try {
        let track = renderer.readAssDocument(styledAssDocument().toArray())
        let bitmap = renderer.render(1000, [track])
        @Expect(nonTransparentPixels(bitmap) > 0)
        @Expect(firstVisibleRow(bitmap) < 90)
    } finally {
        renderer.close()
    }
}

@Test
func unchangedMultiTrackCompositionSkipsRgbaCopy(): Unit {
    let renderer = AssRenderer(320, 180)
    try {
        let firstEvents = ArrayList<PlainSubtitleEvent>()
        firstEvents.add(PlainSubtitleEvent(500, 1500, "First"))
        let secondEvents = ArrayList<PlainSubtitleEvent>()
        secondEvents.add(PlainSubtitleEvent(500, 1500, "Second"))
        let first = renderer.newPlainTrack(firstEvents)
        let second = renderer.newPlainTrack(secondEvents)
        let visible = renderer.render(1000, [first, second])
        @Expect(visible.changed, 1)
        @Expect(nonTransparentPixels(visible) > 0)
        let unchanged = renderer.render(1000, [first, second])
        @Expect(unchanged.changed, 0)
        @Expect(unchanged.rgba.size, 0)
        let cleared = renderer.render(2500, [first, second])
        @Expect(cleared.changed, 1)
        @Expect(cleared.width, 0)
        @Expect(cleared.height, 0)
        @Expect(nonTransparentPixels(cleared), 0)
    } finally {
        renderer.close()
    }
}

@Test
func repeatedConfigureAndCloseAreSafe(): Unit {
    let renderer = AssRenderer(160, 90)
    renderer.configure(320, 180, pixelAspect: 1.0)
    renderer.close()
    renderer.close()
    @Expect(renderer.isClosed())
}

private func nonTransparentPixels(bitmap: SubtitleBitmap): Int64 {
    var count: Int64 = 0
    for (index in 0..(bitmap.rgba.size / 4)) {
        if (bitmap.rgba[index * 4 + 3] != 0u8) {
            count++
        }
    }
    count
}

private func firstVisibleRow(bitmap: SubtitleBitmap): Int64 {
    for (y in 0..Int64(bitmap.height)) {
        for (x in 0..Int64(bitmap.width)) {
            if (bitmap.rgba[(y * Int64(bitmap.width) + x) * 4 + 3] != 0u8) {
                return Int64(bitmap.y) + y
            }
        }
    }
    Int64(bitmap.y + bitmap.height)
}

private func styledAssDocument(): String {
    "[Script Info]\nScriptType: v4.00+\nPlayResX: 320\nPlayResY: 180\n\n" + "[V4+ Styles]\n" +
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, " +
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, " +
        "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n" +
        "Style: Default,DejaVu Sans,28,&H0000FFFF,&H000000FF,&H00000000,&H64000000," +
        "0,0,0,0,100,100,0,0,1,2,1,8,10,10,10,1\n\n" +
        "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n" +
        "Dialogue: 0,0:00:00.50,0:00:02.00,Default,,0,0,0,,Top line\n"
}
