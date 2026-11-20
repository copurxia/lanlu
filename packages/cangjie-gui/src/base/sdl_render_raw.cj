package cui.base

/*
 * Mirrors SDL_Vertex: position, straight-alpha float colour, and texture coordinates.
 * Kept as eight flat Float32 fields so the layout matches the C struct exactly.
 */
@C
internal struct SdlVertex {
    var px: Float32 = 0.0
    var py: Float32 = 0.0
    var colR: Float32 = 0.0
    var colG: Float32 = 0.0
    var colB: Float32 = 0.0
    var colA: Float32 = 0.0
    var tu: Float32 = 0.0
    var tv: Float32 = 0.0
}

foreign {
    // name 传空 CString 即 SDL_CreateRenderer(window, NULL)：按 SDL_RENDER_DRIVER hint
    //（SDL3 支持逗号分隔回退列表）或内置顺序自动选择渲染驱动。
    
    func SDL_DestroyRenderer(renderer: CPointer<Unit>): Unit

    func SDL_SetRenderVSync(renderer: CPointer<Unit>, vsync: Int32): Bool

    
    func SDL_SetRenderDrawBlendMode(renderer: CPointer<Unit>, blendMode: UInt32): Bool

    func SDL_SetRenderScale(renderer: CPointer<Unit>, scaleX: Float32, scaleY: Float32): Bool

    
    
    func SDL_SetRenderClipRect(renderer: CPointer<Unit>, rect: CPointer<SdlRect>): Bool

    
    
    // 当前渲染目标纹理；渲染到窗口时返回空指针。返回的纹理由 SDL 持有，调用方不得销毁。
    
    
    
    
    
    
    func SDL_RenderClear(renderer: CPointer<Unit>): Bool


    



    func SDL_RenderReadPixels(renderer: CPointer<Unit>, rect: CPointer<SdlRect>): CPointer<Unit>

    

    func SDL_CreateTexture(
        renderer: CPointer<Unit>,
        format: UInt32,
        access: Int32,
        w: Int32,
        h: Int32
    ): CPointer<Unit>

    func SDL_SetRenderTarget(renderer: CPointer<Unit>, texture: CPointer<Unit>): Bool

    func SDL_RenderGeometry(
        renderer: CPointer<Unit>,
        texture: CPointer<Unit>,
        vertices: CPointer<SdlVertex>,
        numVertices: Int32,
        indices: CPointer<Int32>,
        numIndices: Int32
    ): Bool
}
