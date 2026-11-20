package cui.system

import lbase.CuiException

import cui.base.{ensureSdl}

internal func appMetadataPropertyName(property: AppMetadataProperty): String {
    match (property) {
        case AppMetadataProperty.Name => "SDL.app.metadata.name"
        case AppMetadataProperty.Version => "SDL.app.metadata.version"
        case AppMetadataProperty.Identifier => "SDL.app.metadata.identifier"
        case AppMetadataProperty.Creator => "SDL.app.metadata.creator"
        case AppMetadataProperty.Copyright => "SDL.app.metadata.copyright"
        case AppMetadataProperty.Url => "SDL.app.metadata.url"
        case AppMetadataProperty.ApplicationType => "SDL.app.metadata.type"
        case AppMetadataProperty.CustomMetadataProperty(value) => value
    }
}

internal func appMetadataTypeValue(appType: AppMetadataType): String {
    match (appType) {
        case AppMetadataType.Application => "application"
        case AppMetadataType.Game => "game"
        case AppMetadataType.MediaPlayer => "mediaplayer"
        case AppMetadataType.CustomMetadataType(value) => value
    }
}

internal func optionalMetadataCString(value: ?String): CString {
    match (value) {
        case Some(text) => unsafe { LibC.mallocCString(text) }
        case None => CString(CPointer<UInt8>())
    }
}

internal func freeMetadataCString(value: CString): Unit {
    if (!value.isNull()) {
        unsafe { LibC.free(value) }
    }
}

internal func setOptionalMetadataProperty(property: AppMetadataProperty, value: ?String): Unit {
    match (value) {
        case Some(text) => ApplicationMetadata.set(property, text)
        case None => ()
    }
}

internal func setOptionalMetadataType(appType: ?AppMetadataType): Unit {
    match (appType) {
        case Some(value) => ApplicationMetadata.set(AppMetadataProperty.ApplicationType, appMetadataTypeValue(value))
        case None => ()
    }
}

internal func withMetadataStrings(property: AppMetadataProperty, value: String, hasValue: Bool): Unit {
    // P5：无 SDL —— 元数据设置变成 no-op（OHOS 由 module.json 声明）
    let _ = (property, value, hasValue)
}

/**
 * Throws `CuiException` when a custom metadata property name is empty.
 */
internal func ensureMetadataName(name: String): Unit {
    if (name.size <= 0) {
        throw CuiException("Application metadata property name cannot be empty.")
    }
}
