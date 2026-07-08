package lanlu.shared.entities

import csorm.*
import csorm_macros.*
import postgresql_driver.*
import std.collection.*

/**
 * lanlu 数据库 @Entity 声明（csorm 阶段二落地）。
 *
 * 基于最终表结构（docs/database-schema.md，v001~v026 全部迁移后的净结果）。
 * 关键注意：
 * - archives 表已"瘦身"（v012/v013 删了 title/summary/cover_asset_id/created_at/updated_at/title_tsv/assets），
 *   故 Archive entity 只含表实际列；视图列（title/summary/release_at/tags 等）走 PartialModel 映射 archive_metadata_search。
 * - tankoubons 表已删 name/summary/cover_asset_id/created_at/updated_at/assets。
 * - archive_tags / tankoubon_tags 表已删除（标签关联在 metadata_tags）。
 * - plugins.login_from 已删除（v023 迁移到 pre_hooks）。
 * - task_group_kv 已删除（v016 迁移到 RocksDB）。
 */

// ===== 用户域 =====

@entity[table = "users"]
public struct UserEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var username: String = ""
    public var password_salt: String = ""
    public var password_hash: String = ""
    public var password_hash_version: String = "sha256_v1"
    public var avatar_asset_id: ?Int64 = None
    public var is_admin: Bool = false
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "user_tokens"]
public struct UserTokenEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var name: String = ""
    public var token_type: String = "session"
    public var token_prefix: String = ""
    public var token_hash: String = ""
    public var created_at: String = ""
    public var last_used_at: ?String = None
    public var revoked_at: ?String = None
    public var last_used_ip: String = ""
    public var user_agent: String = ""
    public var expires_at: ?String = None
}

@entity[table = "user_webauthn_credentials"]
public struct UserWebauthnCredentialEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var name: String = ""
    public var credential_id_b64url: String = ""
    public var algorithm: String = "ES256"
    public var public_key_b64: String = ""
    public var sign_count: Int64 = 0
    public var aaguid: String = ""
    public var transports_json: String = "[]"
    public var user_verified: Bool = false
    public var backup_eligible: Bool = false
    public var backup_state: Bool = false
    public var attestation_format: String = "none"
    public var created_at: String = ""
    public var updated_at: String = ""
    public var last_used_at: ?String = None
    public var revoked_at: ?String = None
}

@entity[table = "user_totp_credentials"]
public struct UserTotpCredentialEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var name: String = ""
    public var secret_b32: String = ""
    public var secret_hash: String = ""
    public var digits: Int32 = 6
    public var period_seconds: Int32 = 30
    public var algorithm: String = "SHA1"
    public var issuer: String = "Lanlu"
    public var created_at: String = ""
    public var updated_at: String = ""
    public var verified_at: ?String = None
    public var last_used_step: Int64 = -1
    public var revoked_at: ?String = None
}

@entity[table = "user_totp_recovery_codes"]
public struct UserTotpRecoveryCodeEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var credential_id: Int64 = 0
    public var code_hash: String = ""
    public var used_at: ?String = None
    public var created_at: String = ""
}

@entity[table = "user_archive_status"]
public struct UserArchiveStatusEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var archive_id: Int64 = 0
    public var is_new: Bool = true
    public var progress: Int32 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "user_favorites"]
public struct UserFavoriteEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var archive_id: Int64 = 0
    public var created_at: String = ""
}

@entity[table = "user_tankoubon_favorites"]
public struct UserTankoubonFavoriteEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var tankoubon_id: Int64 = 0
    public var created_at: String = ""
}

@entity[table = "user_target_status"]
public struct UserTargetStatusEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var target_type: String = ""
    public var target_id: String = ""
    public var is_new: Bool = true
    public var progress: Int32 = 0
    public var last_read_time: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "user_target_favorites"]
public struct UserTargetFavoriteEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var target_type: String = ""
    public var target_id: String = ""
    public var created_at: String = ""
}

// ===== 归档/分类/单行本域 =====

@entity[table = "categories"]
public struct CategoryEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var catid: String = ""
    public var name: String = ""
    public var scan_path: String = ""
    public var description: String = ""
    public var icon: String = ""
    public var sort_order: Int32 = 0
    public var enabled: Bool = true
    public var plugins: String = "[]"
    public var cover_asset_id: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}

/**
 * archives 表（瘦身后，v012/v013 删除了 title/summary/cover_asset_id/created_at/updated_at/title_tsv/assets）。
 * 标题/摘要/时间/封面/标签经 archive_metadata_search 视图或 metadata_objects 读取。
 */
@entity[table = "archives"]
public struct ArchiveEntityStruct {
    @pk[auto]
    public var id: Int64 = 0
    public var arcid: String = ""
    public var filename: String = ""
    public var thumbhash: String = ""
    public var relative_path: String = ""
    public var file_size: Int64 = 0
    public var pagecount: Int32 = 0
    public var archive_type: String = "archive"
    public var category_id: Int64 = 0
}

/**
 * tankoubons 表（瘦身后，v012/v013 删除了 name/summary/cover_asset_id/created_at/updated_at/assets）。
 * 名称经 metadata_objects(entity_type='tankoubon') 读取。
 */
@entity[table = "tankoubons"]
public struct TankoubonEntityStruct {
    @pk[auto]
    public var id: Int64 = 0
    public var tankoubon_id: String = ""
    public var auto_created: Bool = false
    public var source_category_id: ?Int64 = None
    public var source_relative_path: String = ""
}

@entity[table = "tankoubon_archives"]
public struct TankoubonArchiveEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var tankoubon_id: Int64 = 0
    public var archive_id: Int64 = 0
    public var sort_order: Int32 = 0
    public var created_at: String = ""
}

// ===== 标签/元数据域 =====

@entity[table = "tags"]
public struct TagEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var namespace: String = ""
    public var name: String = ""
    @jsonb[]
    public var translations: String = "{}"
    public var icon_asset_id: ?Int64 = None
    public var background_asset_id: ?Int64 = None
    public var links: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "metadata_objects"]
public struct MetadataObjectEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var entity_type: String = ""
    public var entity_id: String = ""
    public var parent_entity_type: String = ""
    public var parent_entity_id: String = ""
    public var title: String = ""
    public var description: String = ""
    public var volume_no: Int32 = 0
    public var order_index: Int32 = 0
    public var page_number: Int32 = 0
    public var entry_path: String = ""
    @jsonb[]
    public var extra_data: String = "{}"
    public var source_namespace: String = ""
    public var release_at: ?String = None
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "metadata_tags"]
public struct MetadataTagEntity {
    @pk[]
    public var metadata_id: Int64 = 0
    @pk[]
    public var tag: String = ""
    public var created_at: String = ""
}

@entity[table = "metadata_assets"]
public struct MetadataAssetEntity {
    @pk[]
    public var metadata_id: Int64 = 0
    @pk[]
    public var slot: String = ""
    public var asset_id: Int64 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}

@entity[table = "metadata_page_assets"]
public struct MetadataPageAssetEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var metadata_id: Int64 = 0
    public var slot: String = ""
    public var asset_id: Int64 = 0
    public var name: String = ""
    public var mime_type: String = ""
    public var kind: String = ""
    public var language: String = ""
    public var order_index: Int32 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
}

// ===== 资产/系统设置 =====

@entity[table = "assets"]
public struct AssetEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var owner_user_id: ?Int64 = None
    public var kind: String = ""
    public var original_filename: String = ""
    public var content_type: String = ""
    public var file_ext: String = "bin"
    public var byte_size: Int64 = 0
    public var thumbhash: String = ""
    public var created_at: String = ""
}

@entity[table = "system_settings"]
public struct SystemSettingEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var key: String = ""
    public var value: String = ""
    public var value_type: String = "string"
    public var category: String = ""
    @jsonb[]
    public var description: String = "{}"
    public var is_encrypted: Bool = false
    public var created_at: String = ""
    public var updated_at: String = ""
}

// ===== 任务域 =====

@entity[table = "tasks"]
public struct TaskEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var task_type: String = ""
    public var status: String = "pending"
    public var progress: Int32 = 0
    public var message: ?String = None
    public var plugin_namespace: ?String = None
    public var parameters: ?String = None
    public var result: ?String = None
    public var priority: Int32 = 50
    public var group_id: ?String = None
    public var timeout_at: ?String = None
    public var trigger_source: ?String = None
    public var wait_for_task_id: ?Int64 = None
    public var phase: ?String = None
    public var waiting_reason: ?String = None
    public var active_key: ?String = None
    public var created_at: String = ""
    public var started_at: ?String = None
    public var completed_at: ?String = None
}

@entity[table = "scheduled_tasks"]
public struct ScheduledTaskEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var cron_expression: String = ""
    public var task_type: String = ""
    public var task_parameters: ?String = None
    public var enabled: Bool = true
    public var priority: Int32 = 50
    public var timeout_seconds: Int32 = 3600
    public var last_run_at: ?String = None
    public var last_run_status: ?String = None
    public var last_error: ?String = None
    public var next_run_at: ?String = None
    public var run_count: Int32 = 0
    public var success_count: Int32 = 0
    public var failure_count: Int32 = 0
    public var created_at: String = ""
    public var updated_at: String = ""
    public var created_by: ?String = None
    public var updated_by: ?String = None
}

// ===== 智能筛选器 =====

@entity[table = "smart_filters"]
public struct SmartFilterEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    @jsonb[]
    public var translations: String = "{}"
    public var icon: String = ""
    public var query: String = ""
    public var sort_by: String = ""
    public var sort_order: String = "desc"
    public var date_from: String = ""
    public var date_to: String = ""
    public var newonly: Bool = false
    public var untaggedonly: Bool = false
    public var sort_order_num: Int32 = 0
    public var enabled: Bool = true
    public var created_at: String = ""
    public var updated_at: String = ""
}

// ===== 插件域 =====

@entity[table = "plugins"]
public struct PluginEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var name: String = ""
    public var version: String = ""
    public var namespace: String = ""
    public var description: String = ""
    public var author: String = ""
    public var entry: String = ""
    public var plugin_type: String = ""
    public var tags: String = ""
    public var url_regex: String = ""
    public var source_id_regex: String = ""
    public var pre_hooks: String = "[]"
    public var after_hooks: String = "[]"
    public var permissions: String = ""
    public var icon: String = ""
    public var enabled: Bool = false
    public var installed: Bool = false
    public var has_schema: Bool = false
    public var parameters: String = "[]"
    public var update_url: String = ""
    public var created_at: String = ""
    public var updated_at: String = ""
}

// ===== 推荐域 =====

@entity[table = "recommendation_impressions"]
public struct RecommendationImpressionEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var session_key: String = ""
    public var scene: String = ""
    public var seed_entity_type: String = ""
    public var seed_entity_id: String = ""
    public var item_type: String = ""
    public var item_id: String = ""
    public var position: Int32 = 0
    public var shown_at: String = ""
}

@entity[table = "recommendation_interactions"]
public struct RecommendationInteractionEntity {
    @pk[auto]
    public var id: Int64 = 0
    public var user_id: Int64 = 0
    public var session_key: String = ""
    public var scene: String = ""
    public var seed_entity_type: String = ""
    public var seed_entity_id: String = ""
    public var item_type: String = ""
    public var item_id: String = ""
    public var interaction_type: String = ""
    public var created_at: String = ""
}