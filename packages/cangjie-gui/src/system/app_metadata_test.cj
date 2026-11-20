package cui.system

import lbase.CuiException

@Test
func appMetadataPropertyNamesMapSdlValues(): Unit {
    // SDL_PROP_APP_METADATA_*_STRING 在绑定里的展开值就是这些字符串字面量
    //（P5 移除 SDL 运行时后不再有这些常量，测试直接按协议值断言）。
    @Expect(appMetadataPropertyName(AppMetadataProperty.Name), "SDL.app.metadata.name")
    @Expect(appMetadataPropertyName(AppMetadataProperty.Version), "SDL.app.metadata.version")
    @Expect(appMetadataPropertyName(AppMetadataProperty.Identifier), "SDL.app.metadata.identifier")
    @Expect(appMetadataPropertyName(AppMetadataProperty.Creator), "SDL.app.metadata.creator")
    @Expect(appMetadataPropertyName(AppMetadataProperty.Copyright), "SDL.app.metadata.copyright")
    @Expect(appMetadataPropertyName(AppMetadataProperty.Url), "SDL.app.metadata.url")
    @Expect(appMetadataPropertyName(AppMetadataProperty.ApplicationType), "SDL.app.metadata.type")
    @Expect(appMetadataPropertyName(AppMetadataProperty.CustomMetadataProperty("cui.test")), "cui.test")
}

@Test
func appMetadataTypeValuesMapSdlValues(): Unit {
    @Expect(appMetadataTypeValue(AppMetadataType.Application), "application")
    @Expect(appMetadataTypeValue(AppMetadataType.Game), "game")
    @Expect(appMetadataTypeValue(AppMetadataType.MediaPlayer), "mediaplayer")
    @Expect(appMetadataTypeValue(AppMetadataType.CustomMetadataType("utility")), "utility")
}

@Test
func appMetadataRejectsEmptyCustomProperty(): Unit {
    @Expect(metadataSetFails(AppMetadataProperty.CustomMetadataProperty("")))
}

private func metadataSetFails(property: AppMetadataProperty): Bool {
    try {
        ApplicationMetadata.set(property, "value")
        false
    } catch (e: CuiException) {
        true
    }
}
