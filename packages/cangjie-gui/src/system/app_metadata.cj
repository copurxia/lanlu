package cui.system

import lbase.CuiException

import cui.base.ensureSdl
public enum AppMetadataType {
    | Application
    | Game
    | MediaPlayer
    | CustomMetadataType(String)
}

public enum AppMetadataProperty {
    | Name
    | Version
    | Identifier
    | Creator
    | Copyright
    | Url
    | ApplicationType
    | CustomMetadataProperty(String)
}

public struct AppMetadata {
    public var name: ?String
    public var version: ?String
    public var identifier: ?String
    public var creator: ?String
    public var copyright: ?String
    public var url: ?String
    public var appType: ?AppMetadataType

    public init(name!: ?String = None, version!: ?String = None, identifier!: ?String = None) {
        this.name = name
        this.version = version
        this.identifier = identifier
        this.creator = None
        this.copyright = None
        this.url = None
        this.appType = None
    }
}

public class ApplicationMetadata {
    /**
     * Throws `CuiException` when SDL cannot apply application metadata.
     */
    public static func apply(metadata: AppMetadata): Unit {
        // P5：应用元数据由 OHOS module.json 声明，运行期不再调用 SDL
        let _ = (metadata.name, metadata.version, metadata.identifier)
    }

    /**
     * Throws `CuiException` when SDL cannot set the metadata property.
     */
    public static func set(property: AppMetadataProperty, value: String): Unit {
        ensureMetadataName(appMetadataPropertyName(property))
        withMetadataStrings(property, value, true)
    }

    /**
     * Throws `CuiException` when SDL cannot remove the metadata property.
     */
    public static func remove(property: AppMetadataProperty): Unit {
        ensureMetadataName(appMetadataPropertyName(property))
        withMetadataStrings(property, "", false)
    }

    /**
     * Throws `CuiException` when the property name is empty.
     */
    public static func get(property: AppMetadataProperty): ?String {
        let name = appMetadataPropertyName(property)
        ensureMetadataName(name)
        // P5：无 SDL —— 应用元数据由 OHOS module.json 提供，这里不再查询
        let _ = name
        None<String>
    }
}
