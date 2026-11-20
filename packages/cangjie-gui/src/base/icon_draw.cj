package cui.base

import lbase.{Canvas, Color, Insets, Pen, Point, Rect, Size, clampF32}

private let ICON_GRID: Float32 = 24.0

public enum IconName {
    | NewDocument
    | OpenFolder
    | Save
    | SaveAs
    | Copy
    | Paste
    | Refresh
    | Trash
    | Pencil
    | User
    | Lock
    | Server
    | Eye
    | EyeOff
    | Brush
    | Calendar
    | Clock
    | Process
    | Calculator
    | Close
    | Plus
    | Upload
    | Download
    | Image
    | Play
    | Stop
    | Music
    | Sparkle
    | Check
    | ChevronLeft
    | ChevronRight
    | ChevronUp
    | ChevronDown
    | Grip
}

/*
 * Vector icons drawn on a 24-unit grid. Every stroke is a thick, round-capped line or bar
 * (see Renderer.strokeLine / strokeRect / strokeCircle) rather than a 1px hairline, so the
 * glyphs read as deliberate 2px strokes once the supersampled frame is resolved. `weight`
 * is the stroke width in device-independent pixels.
 */
public func drawIcon(r: Renderer, icon: IconName, rect: Rect, color: Color, weight!: Float32 = 1.6): Unit {
    let pen = Pen(width: strokeFor(rect, weight), color: color)
    match (icon) {
        case IconName.NewDocument => drawNewDocumentIcon(r, rect, pen)
        case IconName.OpenFolder => drawOpenFolderIcon(r, rect, pen)
        case IconName.Save => drawSaveIcon(r, rect, pen)
        case IconName.SaveAs => drawSaveAsIcon(r, rect, pen)
        case IconName.Copy => drawCopyIcon(r, rect, pen)
        case IconName.Paste => drawPasteIcon(r, rect, pen)
        case IconName.Refresh => drawRefreshIcon(r, rect, pen)
        case IconName.Trash => drawTrashIcon(r, rect, pen)
        case IconName.Pencil => drawPencilIcon(r, rect, pen)
        case IconName.User => drawUserIcon(r, rect, pen)
        case IconName.Lock => drawLockIcon(r, rect, pen)
        case IconName.Server => drawServerIcon(r, rect, pen)
        case IconName.Eye => drawEyeIcon(r, rect, pen)
        case IconName.EyeOff =>
            drawEyeIcon(r, rect, pen)
            r.strokeLine(x(rect, 3.5), y(rect, 20.5), x(rect, 20.5), y(rect, 3.5), pen)
        case IconName.Brush => drawBrushIcon(r, rect, pen)
        case IconName.Calendar => drawCalendarIcon(r, rect, pen)
        case IconName.Clock => drawClockIcon(r, rect, pen)
        case IconName.Process => drawProcessIcon(r, rect, pen)
        case IconName.Calculator => drawCalculatorIcon(r, rect, pen)
        case IconName.Close => drawCloseIcon(r, rect, pen)
        case IconName.Plus => drawPlusIcon(r, rect, pen)
        case IconName.Upload => drawUploadIcon(r, rect, pen)
        case IconName.Download => drawDownloadIcon(r, rect, pen)
        case IconName.Image => drawImageIcon(r, rect, pen)
        case IconName.Play => drawPlayIcon(r, rect, pen)
        case IconName.Stop => drawStopIcon(r, rect, pen)
        case IconName.Music => drawMusicIcon(r, rect, pen)
        case IconName.Sparkle => drawSparkleIcon(r, rect, pen)
        case IconName.Check => drawCheckIcon(r, rect, pen)
        case IconName.ChevronLeft => drawChevronIcon(r, rect, pen, 15.0, 9.0)
        case IconName.ChevronRight => drawChevronIcon(r, rect, pen, 9.0, 15.0)
        case IconName.ChevronUp => drawVerticalChevronIcon(r, rect, pen, 15.0, 9.0)
        case IconName.ChevronDown => drawVerticalChevronIcon(r, rect, pen, 9.0, 15.0)
        case IconName.Grip => drawGripIcon(r, rect, pen)
    }
}

private func drawCloseIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 6.0), y(rect, 6.0), x(rect, 18.0), y(rect, 18.0), pen)
    r.strokeLine(x(rect, 18.0), y(rect, 6.0), x(rect, 6.0), y(rect, 18.0), pen)
}

private func drawPlusIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 12.0), y(rect, 5.0), x(rect, 12.0), y(rect, 19.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 12.0), x(rect, 19.0), y(rect, 12.0), pen)
}

private func drawUploadIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 12.0), y(rect, 4.0), x(rect, 12.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 7.5), y(rect, 8.5), x(rect, 12.0), y(rect, 4.0), pen)
    r.strokeLine(x(rect, 16.5), y(rect, 8.5), x(rect, 12.0), y(rect, 4.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 14.0), x(rect, 5.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 20.0), x(rect, 19.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 19.0), y(rect, 20.0), x(rect, 19.0), y(rect, 14.0), pen)
}

// Upload 的镜像：向下箭头落入托盘。
private func drawDownloadIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 12.0), y(rect, 4.0), x(rect, 12.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 7.5), y(rect, 10.5), x(rect, 12.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 16.5), y(rect, 10.5), x(rect, 12.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 14.0), x(rect, 5.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 20.0), x(rect, 19.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 19.0), y(rect, 20.0), x(rect, 19.0), y(rect, 14.0), pen)
}

private func drawImageIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRoundedRect(gridRect(rect, 3.5, 4.5, 17.0, 15.0), s(rect, 2.0), pen)
    r.strokeCircle(x(rect, 8.5), y(rect, 9.0), s(rect, 1.6), pen, segments: 18)
    r.strokeLine(x(rect, 5.0), y(rect, 17.5), x(rect, 10.0), y(rect, 12.5), pen)
    r.strokeLine(x(rect, 10.0), y(rect, 12.5), x(rect, 13.0), y(rect, 15.5), pen)
    r.strokeLine(x(rect, 13.0), y(rect, 15.5), x(rect, 16.0), y(rect, 12.5), pen)
    r.strokeLine(x(rect, 16.0), y(rect, 12.5), x(rect, 19.0), y(rect, 15.5), pen)
}

private func drawPlayIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 8.0), y(rect, 5.0), x(rect, 18.0), y(rect, 12.0), pen)
    r.strokeLine(x(rect, 18.0), y(rect, 12.0), x(rect, 8.0), y(rect, 19.0), pen)
    r.strokeLine(x(rect, 8.0), y(rect, 19.0), x(rect, 8.0), y(rect, 5.0), pen)
}

private func drawStopIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRoundedRect(gridRect(rect, 6.0, 6.0, 12.0, 12.0), s(rect, 1.5), pen)
}

private func drawMusicIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 10.0), y(rect, 6.0), x(rect, 10.0), y(rect, 17.0), pen)
    r.strokeLine(x(rect, 18.0), y(rect, 4.0), x(rect, 18.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 10.0), y(rect, 6.0), x(rect, 18.0), y(rect, 4.0), pen)
    r.fillCircle(x(rect, 7.5), y(rect, 18.0), s(rect, 2.5), pen.color)
    r.fillCircle(x(rect, 15.5), y(rect, 16.0), s(rect, 2.5), pen.color)
}

private func drawSparkleIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 12.0), y(rect, 3.0), x(rect, 12.0), y(rect, 21.0), pen)
    r.strokeLine(x(rect, 3.0), y(rect, 12.0), x(rect, 21.0), y(rect, 12.0), pen)
    r.strokeLine(x(rect, 6.0), y(rect, 6.0), x(rect, 18.0), y(rect, 18.0), pen)
    r.strokeLine(x(rect, 18.0), y(rect, 6.0), x(rect, 6.0), y(rect, 18.0), pen)
}

private func drawCheckIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 4.0), y(rect, 12.5), x(rect, 9.5), y(rect, 18.0), pen)
    r.strokeLine(x(rect, 9.5), y(rect, 18.0), x(rect, 20.0), y(rect, 6.0), pen)
}

private func drawChevronIcon(r: Renderer, rect: Rect, pen: Pen, fromX: Float32, toX: Float32): Unit {
    r.strokeLine(x(rect, fromX), y(rect, 5.0), x(rect, toX), y(rect, 12.0), pen)
    r.strokeLine(x(rect, toX), y(rect, 12.0), x(rect, fromX), y(rect, 19.0), pen)
}

private func drawVerticalChevronIcon(r: Renderer, rect: Rect, pen: Pen, fromY: Float32, toY: Float32): Unit {
    r.strokeLine(x(rect, 5.0), y(rect, fromY), x(rect, 12.0), y(rect, toY), pen)
    r.strokeLine(x(rect, 12.0), y(rect, toY), x(rect, 19.0), y(rect, fromY), pen)
}

private func drawGripIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    let columns: Array<Float32> = [9.0, 15.0]
    let rows: Array<Float32> = [6.0, 12.0, 18.0]
    for (gx in columns) {
        for (gy in rows) {
            r.fillCircle(x(rect, gx), y(rect, gy), s(rect, 1.4), pen.color)
        }
    }
}

private func drawNewDocumentIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 5.0, 3.0, 11.0, 16.0), pen)
    r.strokeLine(x(rect, 16.0), y(rect, 3.0), x(rect, 19.0), y(rect, 6.0), pen)
    r.strokeLine(x(rect, 19.0), y(rect, 6.0), x(rect, 19.0), y(rect, 21.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 12.0), x(rect, 15.0), y(rect, 12.0), pen)
    r.strokeLine(x(rect, 12.0), y(rect, 9.0), x(rect, 12.0), y(rect, 15.0), pen)
}

private func drawOpenFolderIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 3.0), y(rect, 8.0), x(rect, 9.0), y(rect, 8.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 8.0), x(rect, 11.0), y(rect, 6.0), pen)
    r.strokeLine(x(rect, 11.0), y(rect, 6.0), x(rect, 15.0), y(rect, 6.0), pen)
    r.strokeLine(x(rect, 15.0), y(rect, 6.0), x(rect, 17.0), y(rect, 8.0), pen)
    r.strokeRect(gridRect(rect, 3.0, 8.0, 18.0, 12.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 13.0), x(rect, 19.0), y(rect, 13.0), pen)
}

private func drawSaveIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 4.0, 4.0, 16.0, 16.0), pen)
    r.strokeRect(gridRect(rect, 7.0, 4.0, 9.0, 5.0), pen)
    r.strokeRect(gridRect(rect, 7.0, 14.0, 10.0, 6.0), pen)
}

private func drawSaveAsIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    drawSaveIcon(r, rect, pen)
    r.strokeLine(x(rect, 14.0), y(rect, 14.0), x(rect, 21.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 18.0), y(rect, 7.0), x(rect, 21.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 21.0), y(rect, 7.0), x(rect, 21.0), y(rect, 10.0), pen)
}

private func drawCopyIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 8.0, 7.0, 11.0, 13.0), pen)
    r.strokeRect(gridRect(rect, 5.0, 4.0, 11.0, 13.0), pen)
}

private func drawPasteIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 6.0, 6.0, 12.0, 14.0), pen)
    r.strokeRect(gridRect(rect, 9.0, 3.0, 6.0, 5.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 12.0), x(rect, 15.0), y(rect, 12.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 16.0), x(rect, 15.0), y(rect, 16.0), pen)
}

private func drawRefreshIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeCircle(rect.centerX(), rect.centerY(), s(rect, 7.0), pen, segments: 32)
    r.strokeLine(x(rect, 17.0), y(rect, 4.0), x(rect, 20.0), y(rect, 4.0), pen)
    r.strokeLine(x(rect, 20.0), y(rect, 4.0), x(rect, 20.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 4.0), y(rect, 17.0), x(rect, 4.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 4.0), y(rect, 20.0), x(rect, 7.0), y(rect, 20.0), pen)
}

private func drawPencilIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    // 笔身：两条平行长斜线 + 尾端封口，构成右上→左下的平行四边形。
    r.strokeLine(x(rect, 6.0), y(rect, 17.0), x(rect, 16.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 4.0), y(rect, 19.0), x(rect, 14.0), y(rect, 9.0), pen)
    r.strokeLine(x(rect, 14.0), y(rect, 9.0), x(rect, 16.0), y(rect, 7.0), pen)
    // 笔尖：笔身两条长边向下汇于一点。
    r.strokeLine(x(rect, 6.0), y(rect, 17.0), x(rect, 3.5), y(rect, 20.5), pen)
    r.strokeLine(x(rect, 4.0), y(rect, 19.0), x(rect, 3.5), y(rect, 20.5), pen)
    // 尾端橡皮：笔尾上方的短斜条。
    r.strokeLine(x(rect, 15.0), y(rect, 5.0), x(rect, 18.0), y(rect, 8.0), pen)
}

private func drawUserIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    // 头（圆）+ 肩（两条斜线近似的弧）。
    r.strokeCircle(x(rect, 12.0), y(rect, 8.0), s(rect, 3.5), pen, segments: 24)
    r.strokeLine(x(rect, 5.0), y(rect, 19.5), x(rect, 12.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 12.0), y(rect, 15.0), x(rect, 19.0), y(rect, 19.5), pen)
}

private func drawLockIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    // 锁体 + 平顶锁梁 + 钥匙孔。
    r.strokeRect(gridRect(rect, 6.0, 11.0, 12.0, 9.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 11.0), x(rect, 9.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 15.0), y(rect, 11.0), x(rect, 15.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 7.0), x(rect, 15.0), y(rect, 7.0), pen)
    r.fillCircle(x(rect, 12.0), y(rect, 15.5), s(rect, 1.2), pen.color)
}

private func drawServerIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    // lucide server：上下两台机架 + 各自指示灯（client LoginScreen 同款图形）。
    r.strokeRect(gridRect(rect, 3.0, 4.0, 18.0, 6.0), pen)
    r.strokeRect(gridRect(rect, 3.0, 14.0, 18.0, 6.0), pen)
    r.fillCircle(x(rect, 6.5), y(rect, 7.0), s(rect, 1.0), pen.color)
    r.fillCircle(x(rect, 6.5), y(rect, 17.0), s(rect, 1.0), pen.color)
}

// lucide eye：杏仁轮廓（上下两段多段线近似的弧）+ 瞳孔。
private func drawEyeIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    let upper: Array<(Float32, Float32)> = [(2.5, 12.0), (5.0, 8.5), (8.5, 6.5), (12.0, 6.0), (15.5, 6.5), (19.0, 8.5),
        (21.5, 12.0)]
    let lower: Array<(Float32, Float32)> = [(2.5, 12.0), (5.0, 15.5), (8.5, 17.5), (12.0, 18.0), (15.5, 17.5),
        (19.0, 15.5), (21.5, 12.0)]
    for (i in 0..upper.size - 1) {
        r.strokeLine(x(rect, upper[i][0]), y(rect, upper[i][1]), x(rect, upper[i + 1][0]), y(rect, upper[i + 1][1]), pen)
        r.strokeLine(x(rect, lower[i][0]), y(rect, lower[i][1]), x(rect, lower[i + 1][0]), y(rect, lower[i + 1][1]), pen)
    }
    r.strokeCircle(x(rect, 12.0), y(rect, 12.0), s(rect, 2.5), pen, segments: 20)
}

private func drawTrashIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 6.0), y(rect, 7.0), x(rect, 18.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 9.0), y(rect, 4.0), x(rect, 15.0), y(rect, 4.0), pen)
    r.strokeRect(gridRect(rect, 7.0, 8.0, 10.0, 12.0), pen)
    r.strokeLine(x(rect, 10.0), y(rect, 10.0), x(rect, 10.0), y(rect, 18.0), pen)
    r.strokeLine(x(rect, 14.0), y(rect, 10.0), x(rect, 14.0), y(rect, 18.0), pen)
}

private func drawBrushIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeLine(x(rect, 14.0), y(rect, 4.0), x(rect, 20.0), y(rect, 10.0), pen)
    r.strokeLine(x(rect, 20.0), y(rect, 10.0), x(rect, 10.0), y(rect, 20.0), pen)
    r.strokeLine(x(rect, 10.0), y(rect, 20.0), x(rect, 6.0), y(rect, 16.0), pen)
    r.strokeLine(x(rect, 6.0), y(rect, 16.0), x(rect, 16.0), y(rect, 6.0), pen)
    r.strokeLine(x(rect, 5.0), y(rect, 18.0), x(rect, 3.0), y(rect, 21.0), pen)
}

private func drawCalendarIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 4.0, 5.0, 16.0, 15.0), pen)
    r.strokeLine(x(rect, 4.0), y(rect, 10.0), x(rect, 20.0), y(rect, 10.0), pen)
    r.strokeLine(x(rect, 8.0), y(rect, 3.0), x(rect, 8.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 16.0), y(rect, 3.0), x(rect, 16.0), y(rect, 7.0), pen)
    r.fillCircle(x(rect, 9.0), y(rect, 15.0), s(rect, 1.3), pen.color)
    r.fillCircle(x(rect, 14.0), y(rect, 15.0), s(rect, 1.3), pen.color)
}

// A round clock face with a long minute hand pointing up and a short hour hand pointing right (~3 o'clock).
private func drawClockIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeCircle(x(rect, 12.0), y(rect, 12.0), s(rect, 8.5), pen, segments: 32)
    r.strokeLine(x(rect, 12.0), y(rect, 12.0), x(rect, 12.0), y(rect, 7.0), pen)
    r.strokeLine(x(rect, 12.0), y(rect, 12.0), x(rect, 15.5), y(rect, 13.5), pen)
}

private func drawProcessIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 5.0, 5.0, 14.0, 14.0), pen)
    r.strokeRect(gridRect(rect, 9.0, 9.0, 6.0, 6.0), pen)
    r.strokeLine(x(rect, 2.0), y(rect, 9.0), x(rect, 5.0), y(rect, 9.0), pen)
    r.strokeLine(x(rect, 2.0), y(rect, 15.0), x(rect, 5.0), y(rect, 15.0), pen)
    r.strokeLine(x(rect, 19.0), y(rect, 9.0), x(rect, 22.0), y(rect, 9.0), pen)
    r.strokeLine(x(rect, 19.0), y(rect, 15.0), x(rect, 22.0), y(rect, 15.0), pen)
}

private func drawCalculatorIcon(r: Renderer, rect: Rect, pen: Pen): Unit {
    r.strokeRect(gridRect(rect, 6.0, 3.0, 12.0, 18.0), pen)
    r.strokeRect(gridRect(rect, 8.0, 6.0, 8.0, 4.0), pen)
    r.fillCircle(x(rect, 9.0), y(rect, 14.0), s(rect, 1.3), pen.color)
    r.fillCircle(x(rect, 13.0), y(rect, 14.0), s(rect, 1.3), pen.color)
    r.fillCircle(x(rect, 9.0), y(rect, 18.0), s(rect, 1.3), pen.color)
    r.fillCircle(x(rect, 13.0), y(rect, 18.0), s(rect, 1.3), pen.color)
}

// Builds a rectangle whose corner and size are given in 24-grid units.
private func gridRect(rect: Rect, gx: Float32, gy: Float32, gw: Float32, gh: Float32): Rect {
    Rect(x(rect, gx), y(rect, gy), s(rect, gw), s(rect, gh))
}

// Keeps the stroke proportional to the icon so large icons are not hairlines and tiny ones
// do not turn into blobs.
private func strokeFor(rect: Rect, weight: Float32): Float32 {
    let scaled = min(rect.w, rect.h) / ICON_GRID * 2.2
    if (scaled > weight) {
        scaled
    } else {
        weight
    }
}

private func x(rect: Rect, value: Float32): Float32 {
    rect.x + rect.w * value / ICON_GRID
}

private func y(rect: Rect, value: Float32): Float32 {
    rect.y + rect.h * value / ICON_GRID
}

private func s(rect: Rect, value: Float32): Float32 {
    min(rect.w, rect.h) * value / ICON_GRID
}
