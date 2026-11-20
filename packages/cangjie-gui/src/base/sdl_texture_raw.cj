package cui.base

foreign {
    func SDL_CreateTextureFromSurface(renderer: CPointer<Unit>, surface: CPointer<Unit>): CPointer<Unit>

    
    func SDL_GetTextureSize(texture: CPointer<Unit>, w: CPointer<Float32>, h: CPointer<Float32>): Bool

    // streaming 纹理原地整图更新（rect 传空指针）：pixels 按 pitch 字节行距解释。
    func SDL_UpdateTexture(texture: CPointer<Unit>, rect: CPointer<SdlRect>, pixels: CPointer<UInt8>, pitch: Int32): Bool

    
    
    
    
    
    
    }
