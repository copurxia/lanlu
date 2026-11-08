package lanlu.shared.entities

import csorm.*

/**
 * lanlu 实体关系定义（csorm 阶段一落地）。
 *
 * 基于最终表结构的外键关系。注意：
 * - archive→tags 不走经典中间表（archive_tags 已删），标签关联在 metadata_tags，
 *   故不在此声明 Archive hasMany Tag，而是走 MetadataObject 链路。
 * - archives/tankoubons 的标题/封面等元数据经 metadata_objects 读取，
 *   Archive/Tankoubon 与 MetadataObject 是 entity_id(arcid/tankoubon_id) 关联，非 PK 外键。
 */

/**
 * User hasMany UserToken（user_tokens.user_id → users.id）。
 */
public func userHasTokens(): RelationDef {
    RelationDef.hasMany(userEntityEntity(), userTokenEntityEntity(), "user_id")
}

/**
 * User hasMany UserArchiveStatus（user_archive_status.user_id → users.id）。
 */
public func userHasArchiveStatus(): RelationDef {
    RelationDef.hasMany(userEntityEntity(), userArchiveStatusEntityEntity(), "user_id")
}

/**
 * User hasMany UserFavorite（user_favorites.user_id → users.id）。
 */
public func userHasFavorites(): RelationDef {
    RelationDef.hasMany(userEntityEntity(), userFavoriteEntityEntity(), "user_id")
}

/**
 * User hasMany UserWebauthnCredential（user_webauthn_credentials.user_id → users.id）。
 */
public func userHasWebauthnCredentials(): RelationDef {
    RelationDef.hasMany(userEntityEntity(), userWebauthnCredentialEntityEntity(), "user_id")
}

/**
 * User hasMany UserTotpCredential（user_totp_credentials.user_id → users.id）。
 */
public func userHasTotpCredentials(): RelationDef {
    RelationDef.hasMany(userEntityEntity(), userTotpCredentialEntityEntity(), "user_id")
}

/**
 * Category hasMany Archive（archives.category_id → categories.id）。
 */
public func categoryHasArchives(): RelationDef {
    RelationDef.hasMany(categoryEntityEntity(), archiveEntityStructEntity(), "category_id")
}

/**
 * Archive hasMany TankoubonArchive（tankoubon_archives.archive_id → archives.id）。
 */
public func archiveHasTankoubonArchives(): RelationDef {
    RelationDef.hasMany(archiveEntityStructEntity(), tankoubonArchiveEntityEntity(), "archive_id")
}

/**
 * Tankoubon hasMany TankoubonArchive（tankoubon_archives.tankoubon_id → tankoubons.id）。
 */
public func tankoubonHasTankoubonArchives(): RelationDef {
    RelationDef.hasMany(tankoubonEntityStructEntity(), tankoubonArchiveEntityEntity(), "tankoubon_id")
}

/**
 * MetadataObject hasMany MetadataTag（metadata_tags.metadata_id → metadata_objects.id）。
 */
public func metadataObjectHasTags(): RelationDef {
    RelationDef.hasMany(metadataObjectEntityEntity(), metadataTagEntityEntity(), "metadata_id")
}

/**
 * MetadataObject hasMany MetadataAsset（metadata_assets.metadata_id → metadata_objects.id）。
 */
public func metadataObjectHasAssets(): RelationDef {
    RelationDef.hasMany(metadataObjectEntityEntity(), metadataAssetEntityEntity(), "metadata_id")
}

/**
 * MetadataObject hasMany MetadataPageAsset（metadata_page_assets.metadata_id → metadata_objects.id）。
 */
public func metadataObjectHasPageAssets(): RelationDef {
    RelationDef.hasMany(metadataObjectEntityEntity(), metadataPageAssetEntityEntity(), "metadata_id")
}

/**
 * UserTotpCredential hasMany UserTotpRecoveryCode（user_totp_recovery_codes.credential_id → user_totp_credentials.id）。
 */
public func totpCredentialHasRecoveryCodes(): RelationDef {
    RelationDef.hasMany(userTotpCredentialEntityEntity(), userTotpRecoveryCodeEntityEntity(), "credential_id")
}