package cui.base

import std.collection.ArrayList
import std.collection.concurrent.ConcurrentHashMap

internal let SDL_HITTEST_NORMAL: Int32 = 0
internal let SDL_HITTEST_DRAGGABLE: Int32 = 1

// Drag regions in SDL window pixels (logical gui coordinates x window scale), keyed by SDL
// window pointer so a single @C hit-test callback serves every window. Each window may own
// several rectangles: a custom title bar typically keeps interactive controls (search box,
// buttons) outside the drag area, leaving one rectangle per gap. Stale entries are
// harmless: the callback is only installed on windows that registered regions, and
// registering again overwrites the entry.
private let DRAG_REGIONS = ConcurrentHashMap<UIntNative, ArrayList<SdlRect>>(concurrencyLevel: 2)

// Replaces the window's drag region list with the given rectangles (logical gui coordinates).
private func storeDragRegions(window: CPointer<Unit>, rects: Array<(Int32, Int32, Int32, Int32)>,
    scale: Float32): Unit {
    let list = ArrayList<SdlRect>()
    for (r in rects) {
        let (x, y, w, h) = r
        var region = SdlRect()
        region.x = scaledDimension(x, scale)
        region.y = scaledDimension(y, scale)
        region.w = scaledDimension(w, scale)
        region.h = scaledDimension(h, scale)
        list.add(region)
    }
    let _ = DRAG_REGIONS.add(window.toUIntNative(), list)
}

internal func registerDragRegion(
    window: CPointer<Unit>,
    x: Int32,
    y: Int32,
    width: Int32,
    height: Int32,
    scale: Float32
): Unit {
    storeDragRegions(window, [(x, y, width, height)], scale)
}

internal func registerDragRegions(
    window: CPointer<Unit>,
    rects: Array<(Int32, Int32, Int32, Int32)>,
    scale: Float32
): Unit {
    storeDragRegions(window, rects, scale)
}

internal func unregisterDragRegion(window: CPointer<Unit>): Unit {
    let _ = DRAG_REGIONS.remove(window.toUIntNative())
}

@C
func cuiWindowDragHitTest(window: CPointer<Unit>, area: CPointer<SdlPoint>, data: CPointer<Unit>): Int32 {
    let _ = data
    if (window.isNull() || area.isNull()) {
        return SDL_HITTEST_NORMAL
    }
    let point = unsafe { area.read() }
    match (DRAG_REGIONS.get(window.toUIntNative())) {
        case Some(regions) =>
            for (region in regions) {
                if (point.x >= region.x && point.x < region.x + region.w && point.y >= region.y &&
                    point.y < region.y + region.h) {
                    return SDL_HITTEST_DRAGGABLE
                }
            }
        case None => ()
    }
    SDL_HITTEST_NORMAL
}
