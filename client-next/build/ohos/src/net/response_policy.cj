package lanlu_client_next.net

import std.collection.ArrayList

// ---- 离线响应缓存集中策略表 ----
// 白名单由本表集中维护：每个端点声明 TTL（在线缓存命中窗口）与是否允许 stale offline
// （离线模式按策略读取过期记录）。业务代码只查 policyFor(path)，不在各 API 方法散落判断。
// 路径前缀按“最长匹配”命中；未命中走默认策略。

public let RESPONSE_TTL_ME: Int64 = 60 * 60 * 1000 // 1 小时
public let RESPONSE_TTL_SHORT: Int64 = 5 * 60 * 1000 // 5 分钟
public let RESPONSE_TTL_DAY: Int64 = 24 * 60 * 60 * 1000 // 24 小时

public class ResponsePolicy {
    public let pathPrefix: String
    public let ttlMs: Int64
    public let allowStaleOffline: Bool

    public init(pathPrefix: String, ttlMs: Int64, allowStaleOffline: Bool) {
        this.pathPrefix = pathPrefix
        this.ttlMs = ttlMs
        this.allowStaleOffline = allowStaleOffline
    }
}

// 默认策略：任何 GET 响应都可以离线回退，但 stale 只在明确允许的端点上读取。
private let DEFAULT_RESPONSE_POLICY = ResponsePolicy("", RESPONSE_TTL_ME, false)

public let RESPONSE_POLICIES: Array<ResponsePolicy> = [
    // 会话与用户信息：短 TTL，不允许 stale（换账号/登出后不得回退旧身份）。
    ResponsePolicy("/api/auth/me", RESPONSE_TTL_SHORT, false),
    // 搜索与推荐：中 TTL，允许 stale 离线（搜索结果会随收藏/已读变化，见 invalidation registry）。
    ResponsePolicy("/api/search", RESPONSE_TTL_ME, true),
    ResponsePolicy("/api/recommendations", RESPONSE_TTL_ME, true),
    // 分类与标签翻译：低频变化，长 TTL，允许 stale。
    ResponsePolicy("/api/categories", RESPONSE_TTL_DAY, true),
    ResponsePolicy("/api/tags/translations", RESPONSE_TTL_DAY, true),
    // 档案元数据、页表与所属合集：中 TTL，允许 stale。
    ResponsePolicy("/api/archives/", RESPONSE_TTL_ME, true),
    // 合集列表与详情：中 TTL，允许 stale。
    ResponsePolicy("/api/tankoubons", RESPONSE_TTL_ME, true),
    // 统计与标签云：短 TTL，不允许 stale（数字应尽量接近实时，且仅作在线 session cache）。
    ResponsePolicy("/api/user/", RESPONSE_TTL_SHORT, false),
    ResponsePolicy("/api/tags/cloud", RESPONSE_TTL_SHORT, false),
    // 标签页/命名空间（管理只读）：短 TTL 在线 session cache。
    ResponsePolicy("/api/tags", RESPONSE_TTL_SHORT, false),
    // 管理对象：短 TTL 在线 session cache，不允许 stale（离线不承诺管理操作）。
    ResponsePolicy("/api/auth/admin/users", RESPONSE_TTL_SHORT, false),
    ResponsePolicy("/api/admin/", RESPONSE_TTL_SHORT, false)
]

// 返回最长匹配的策略；无匹配返回默认。
public func responsePolicyFor(path: String): ResponsePolicy {
    var best: ?ResponsePolicy = None
    var bestLength: Int64 = -1
    for (policy in RESPONSE_POLICIES) {
        if (policy.pathPrefix.size > bestLength && path.startsWith(policy.pathPrefix)) {
            best = Some(policy)
            bestLength = policy.pathPrefix.size
        }
    }
    return best ?? DEFAULT_RESPONSE_POLICY
}

// 安全页数据（会话/令牌/通行密钥/TOTP 及账号操作）必须在线读取，从未落普通缓存。
// 即使业务误调 checkedBodyCached/storeResponse，此守卫也会拒绝落库。
private let NON_CACHEABLE_PREFIXES: Array<String> = [
    "/api/auth/sessions",
    "/api/auth/tokens",
    "/api/auth/webauthn",
    "/api/auth/totp",
    "/api/auth/username",
    "/api/auth/password"
]

public func isCacheablePath(path: String): Bool {
    for (prefix in NON_CACHEABLE_PREFIXES) {
        if (path.startsWith(prefix)) {
            return false
        }
    }
    return true
}

// ---- mutation → 受影响响应前缀（invalidation registry）----
// 集中声明：某类 mutation 成功后必须精确删除/过期哪些缓存响应，避免无限返回旧离线快照。
// kind 是 mutation 类型，target 是实体 id（arcid/tankid/catid/tag 等）；返回需要失效的
// resp path 前缀列表。不在各 API 方法里散落 delete key 逻辑。

public func invalidatedResponsePrefixes(kind: String, target: String): ArrayList<String> {
    let out = ArrayList<String>()
    let arc = "/api/archives/${target}"
    let tank = "/api/tankoubons/${target}"
    match (kind) {
        case "archive-meta" =>
            out.add("${arc}/metadata")
            out.add("${arc}/files")
            out.add("/api/search")
        case "archive-favorite" =>
            out.add("${arc}/metadata")
            out.add("/api/search")
            out.add("/api/recommendations")
            out.add("${arc}/tankoubons")
        case "archive-new" =>
            out.add("${arc}/metadata")
            out.add("/api/search")
        case "archive-progress" =>
            out.add("${arc}/metadata")
            out.add("/api/search")
        case "archive-delete" =>
            out.add("${arc}")
            out.add("/api/search")
            out.add("/api/recommendations")
        case "tank-meta" =>
            out.add("${tank}/metadata")
            out.add("/api/tankoubons")
            out.add("/api/search")
        case "tank-favorite" =>
            out.add("${tank}/metadata")
            out.add("/api/tankoubons")
            out.add("/api/search")
        case "tank-member" =>
            out.add("${tank}/metadata")
            out.add("${tank}/")
            out.add("/api/search")
            out.add("/api/recommendations")
        case "tank-delete" =>
            out.add("${tank}")
            out.add("/api/search")
        case "category" =>
            out.add("/api/categories")
            out.add("/api/search")
        case "tag" =>
            out.add("/api/tags/translations")
            out.add("/api/search")
        case "user-stats" =>
            out.add("/api/user/stats")
            out.add("/api/user/trend")
            out.add("/api/tags/cloud")
        case "admin-user" =>
            out.add("/api/auth/admin/users")
        case "system-settings" =>
            out.add("/api/admin/system/settings")
        case "admin-category" =>
            out.add("/api/admin/categories")
            out.add("/api/categories")
            out.add("/api/search")
        case "admin-tag" =>
            out.add("/api/admin/tags")
            out.add("/api/tags/translations")
            out.add("/api/tags/cloud")
            out.add("/api/search")
        case "smart-filter" =>
            out.add("/api/admin/smart_filters")
        case "plugin" =>
            out.add("/api/admin/plugins")
        case "cron" =>
            out.add("/api/admin/cron")
        case "taskpool" =>
            out.add("/api/admin/taskpool")
        case _ => ()
    }
    return out
}
