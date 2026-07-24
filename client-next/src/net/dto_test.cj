package lanlu_client_next.net

@Test
func envelopeParsesCodeMessageData(): Unit {
    let env = parseEnvelope("{\"code\":200,\"message\":\"ok\",\"data\":{\"a\":1}}")
    @Expect(env.code, 0 + 200)
    @Expect(env.message, "ok")
    @Expect(env.dataRaw.contains("\"a\":1"))
}

@Test
func loginDataReadsNestedUserAndToken(): Unit {
    let body = "{\"user\":{\"id\":7,\"username\":\"alice\",\"isAdmin\":true,\"avatarAssetId\":0},\"token\":{\"id\":3,\"name\":\"login\",\"prefix\":\"ab\",\"token\":\"secret-token\"}}"
    let d = JsonCodec.decode<LoginData>(body)
    @Expect(d.token, "secret-token")
    @Expect(d.username, "alice")
    @Expect(d.isAdmin, true)
    @Expect(d.userId, 7)
}

@Test
func searchPageParsesItemsWithCsvTagsAndAssetsObject(): Unit {
    let body = "{\"data\":[{\"type\":\"archive\",\"arcid\":\"a1\",\"archivetype\":\"image\",\"filename\":\"f.cbz\",\"isnew\":true,\"isfavorite\":false,\"favoritetime\":0,\"lastreadtime\":0,\"pagecount\":24,\"progress\":3,\"size\":12345,\"assets\":{\"cover\":42},\"description\":\"d\",\"tags\":\"tag1, ns:tag2\",\"title\":\"Title1\",\"release_at\":0,\"created_at\":0,\"updated_at\":0}],\"draw\":1,\"page\":2,\"pageSize\":40,\"recordsFiltered\":57,\"recordsTotal\":57}"
    let p = parseSearchPage(body)
    @Expect(p.items.size, 1)
    @Expect(p.items[0].arcid, "a1")
    @Expect(p.items[0].tagsCsv, "tag1, ns:tag2")
    @Expect(p.items[0].coverAssetId, 42)
    @Expect(p.items[0].pagecount, 24)
    @Expect(p.items[0].isnew, true)
    @Expect(p.page, 2)
    @Expect(p.recordsTotal, 57)
}

@Test
func archiveMetaParsesArrayTagsAndAssetsArray(): Unit {
    let body = "{\"code\":200,\"message\":\"ok\",\"data\":{\"arcid\":\"a1\",\"title\":\"T\",\"description\":\"d\",\"tags\":[\"x\",\"y:z\"],\"assets\":[{\"key\":\"cover\",\"value\":42}],\"pagecount\":24,\"progress\":3,\"size\":1000,\"isnew\":false,\"isfavorite\":true,\"archivetype\":\"image\",\"filename\":\"f.cbz\",\"thumbnail_hash\":\"abc\",\"capabilities\":[\"read\",\"progress\"]}}"
    let m = parseArchiveMeta(body)
    @Expect(m.arcid, "a1")
    @Expect(m.tags.size, 2)
    @Expect(m.tags[1], "y:z")
    @Expect(m.coverAssetId, 42)
    @Expect(m.isfavorite, true)
    @Expect(m.capabilities.size, 2)
}

@Test
func archiveMetaParsesRawObjectWithoutEnvelope(): Unit {
    // 服务端真实形态：/api/archives/:id/metadata 返回裸 JSON 对象（无 code/message/data 包络），大小字段为 file_size。
    let body = "{\"arcid\":\"a9\",\"title\":\"Raw Title\",\"type\":0,\"description\":\"raw desc\",\"tags\":[\"t1\",\"ns:t2\"],\"assets\":[{\"key\":\"cover\",\"value\":123}],\"children\":[],\"filename\":\"raw.cbz\",\"relative_path\":\"dir/raw.cbz\",\"file_size\":987654,\"pagecount\":30,\"progress\":5,\"isnew\":true,\"isfavorite\":false,\"lastreadtime\":0,\"archivetype\":\"archive\",\"release_at\":0,\"created_at\":0,\"updated_at\":0,\"thumbnail_hash\":\"deadbeef\",\"capabilities\":[\"read\",\"download_cover\"]}"
    let m = parseArchiveMeta(body)
    @Expect(m.arcid, "a9")
    @Expect(m.title, "Raw Title")
    @Expect(m.tags.size, 2)
    @Expect(m.tags[1], "ns:t2")
    @Expect(m.coverAssetId, 123)
    @Expect(m.size, 987654)
    @Expect(m.pagecount, 30)
    // 时间戳字段：服务端真实响应包含 release_at/created_at/updated_at/lastreadtime
    @Expect(m.release_at, 0)
    @Expect(m.created_at, 0)
    @Expect(m.updated_at, 0)
    @Expect(m.lastreadtime, 0)
}

@Test
func archiveMetaEnvelopeWithFileSizeStillParses(): Unit {
    // 回归：包络形态 + file_size 字段名仍正确解析（size 写入 res.size）。
    let body = "{\"code\":200,\"message\":\"ok\",\"data\":{\"arcid\":\"a1\",\"title\":\"T\",\"tags\":[\"x\"],\"assets\":[{\"key\":\"cover\",\"value\":7}],\"file_size\":2048,\"pagecount\":10,\"isnew\":false,\"isfavorite\":true}}"
    let m = parseArchiveMeta(body)
    @Expect(m.arcid, "a1")
    @Expect(m.size, 2048)
    @Expect(m.coverAssetId, 7)
    @Expect(m.isfavorite, true)
}

@Test
func unwrapDataRawReturnsDataContentWhenPresent(): Unit {
    // 有 "data" 键 → 返回 data 的原始 JSON 文本。
    let raw = unwrapDataRaw("{\"code\":200,\"message\":\"ok\",\"data\":{\"x\":1}}")
    @Expect(raw.contains("\"x\":1"))
}

@Test
func unwrapDataRawReturnsBodyWhenNoDataKey(): Unit {
    // 无 "data" 键 → 原样返回整个 body。
    let body = "{\"name\":\"lanlu\",\"version\":\"1.2.3\"}"
    @Expect(unwrapDataRaw(body), body)
}

@Test
func unwrapDataRawEmptyStringReturnedAsIs(): Unit {
    // 空串 → 原样返回。
    @Expect(unwrapDataRaw(""), "")
}

@Test
func serverInfoDecodesFromRawInfoObject(): Unit {
    // 服务端真实形态：/api/info 返回裸对象（无包络），经 unwrapDataRaw 后解码。
    let body = "{\"motd\":\"hello\",\"name\":\"lanlu\",\"total_archives\":57,\"total_pages_read\":1234,\"version\":\"1.2.3\",\"version_desc\":\"desc\",\"version_name\":\"Cangjie\",\"db_extensions\":[{\"name\":\"pg_trgm\",\"enabled\":true,\"version\":\"1.6\"}]}"
    let info = JsonCodec.decode<ServerInfo>(unwrapDataRaw(body))
    @Expect(info.name, "lanlu")
    @Expect(info.version, "1.2.3")
    @Expect(info.totalArchives, 57)
    @Expect(info.totalPagesRead, 1234)
    @Expect(info.versionDesc, "desc")
    @Expect(info.dbExtensions.size, 1)
    @Expect(info.dbExtensions[0].name, "pg_trgm")
    @Expect(info.dbExtensions[0].enabled)
    @Expect(info.motd, "hello")
}

@Test
func categoriesParseFromEnvelopeDataArray(): Unit {
    let body = "{\"code\":200,\"message\":\"ok\",\"data\":{\"operation\":\"get_categories\",\"data\":[{\"id\":1,\"catid\":\"CAT_1\",\"name\":\"默认\",\"archive_count\":12}],\"success\":1}}"
    // 注意：若真实响应里 categories 数组在 envelope data 内再嵌套一层，本测试驱动实现按真实形态解析。
    let list = parseCategoryList(body)
    @Expect(list.size, 1)
    @Expect(list[0].catid, "CAT_1")
    @Expect(list[0].archiveCount, 12)
}

@Test
func categoriesParseRealTopLevelArrayShape(): Unit {
    // 服务端真实响应：data 直接在顶层且为数组（无 code/message envelope）。
    let body = "{\"operation\":\"get_categories\",\"data\":[{\"id\":2,\"catid\":\"CAT_2\",\"name\":\"真实\",\"archive_count\":3}],\"success\":1}"
    let list = parseCategoryList(body)
    @Expect(list.size, 1)
    @Expect(list[0].catid, "CAT_2")
    @Expect(list[0].archiveCount, 3)
}

@Test
func pagesParseBothShapes(): Unit {
    let direct = "{\"pages\":[{\"id\":\"p/001.jpg\",\"type\":\"image\",\"title\":\"1\"}]}"
    let nested = "{\"code\":200,\"message\":\"ok\",\"data\":{\"pages\":[{\"id\":\"p/002.jpg\",\"type\":\"image\",\"title\":\"2\"}]}}"
    @Expect(parsePages(direct)[0].id, "p/001.jpg")
    @Expect(parsePages(nested)[0].id, "p/002.jpg")
}

@Test
func nullScalarFieldsFallBackToDefaults(): Unit {
    let body = "{\"data\":[{\"type\":\"archive\",\"arcid\":\"a2\",\"archivetype\":\"image\",\"filename\":\"f\",\"isnew\":false,\"isfavorite\":false,\"favoritetime\":null,\"lastreadtime\":null,\"pagecount\":1,\"progress\":0,\"size\":1,\"assets\":{},\"description\":null,\"tags\":\"\",\"title\":\"t\",\"release_at\":0,\"created_at\":0,\"updated_at\":0}],\"draw\":1,\"page\":1,\"pageSize\":1,\"recordsFiltered\":1,\"recordsTotal\":1}"
    let p = parseSearchPage(body)
    @Expect(p.items[0].lastreadtime, 0)
    @Expect(p.items[0].description, "")
}

// E4: 时间戳字段解析与格式化
@Test
func archiveMetaParsesTimestamps(): Unit {
    let body = "{\"arcid\":\"a1\",\"title\":\"T\",\"release_at\":1716076800,\"created_at\":1715904000,\"updated_at\":1716163200,\"lastreadtime\":1716249600,\"pagecount\":10,\"tags\":[]}"
    let m = parseArchiveMeta(body)
    @Expect(m.release_at, 1716076800)
    @Expect(m.created_at, 1715904000)
    @Expect(m.updated_at, 1716163200)
    @Expect(m.lastreadtime, 1716249600)
}

@Test
func formatTimestampReturnsDateString(): Unit {
    // 2024-05-19 00:00:00 UTC = 1716076800
    @Expect(formatTimestamp(1716076800), "2024-05-19")
    // 2024-01-01 00:00:00 UTC = 1704067200
    @Expect(formatTimestamp(1704067200), "2024-01-01")
    // 0 → "未知"
    @Expect(formatTimestamp(0), "未知")
    // 负数 → "未知"
    @Expect(formatTimestamp(-1), "未知")
}

// ===== T10: 合集（tankoubon）DTO + 混合页统计 + HomeItem =====

// 服务端真实形态（Tankoubon.writeJson）：GET /api/tankoubons 返回裸 JSON
// {"filtered":N,"result":[...],"total":N}，无 code/message/data 包络；
// children 为字符串数组，assets 为对象。
@Test
func tankoubonListParsesBareResultArray(): Unit {
    let body = "{\"filtered\":2,\"result\":[{\"tankoubon_id\":\"TANK_1\",\"title\":\"合集一\",\"description\":\"d1\",\"tags\":\"t1\",\"assets\":{\"cover\":42},\"children\":[\"a1\",\"a2\"],\"archive_count\":2,\"pagecount\":48,\"progress\":12,\"lastreadtime\":0,\"release_at\":\"\",\"created_at\":\"\",\"updated_at\":\"2024-05-01\",\"isnew\":true,\"isfavorite\":false},{\"tankoubon_id\":\"TANK_2\",\"title\":\"合集二\",\"description\":\"\",\"tags\":\"\",\"assets\":{},\"children\":[],\"archive_count\":0,\"pagecount\":0,\"progress\":0,\"lastreadtime\":0,\"release_at\":\"\",\"created_at\":\"\",\"updated_at\":\"\",\"isnew\":false,\"isfavorite\":false}],\"total\":2}"
    let list = parseTankoubonList(body)
    @Expect(list.size, 2)
    @Expect(list[0].id, "TANK_1")
    @Expect(list[0].name, "合集一")
    @Expect(list[0].archiveCount, 2)
    @Expect(list[0].totalPages, 48)
    @Expect(list[0].progress, Float32(12.0))
    // 封面档案 id = 首个成员（children[0]），对齐 frontend TankoubonCard firstArchiveId。
    @Expect(list[0].coverArcid, "a1")
    @Expect(list[0].updatedAt, "2024-05-01")
    @Expect(list[1].id, "TANK_2")
    @Expect(list[1].coverArcid, "")
}

// frontend normalizeResult 兼容 result 为单个对象的形态。
@Test
func tankoubonListParsesSingleObjectResult(): Unit {
    let body = "{\"filtered\":1,\"result\":{\"tankoubon_id\":\"TANK_S\",\"title\":\"单本\",\"children\":[\"a9\"],\"archive_count\":1,\"pagecount\":24,\"progress\":3,\"updated_at\":\"2024-05-02\"},\"total\":1}"
    let list = parseTankoubonList(body)
    @Expect(list.size, 1)
    @Expect(list[0].id, "TANK_S")
    @Expect(list[0].coverArcid, "a9")
}

// 单个合集：GET /api/tankoubons/:id/metadata 返回裸对象，children 为 member
// 对象数组（entity_id 指向档案 arcid），assets 为 [{key,value}] 数组。
@Test
func tankoubonParsesMetadataObjectShape(): Unit {
    let body = "{\"title\":\"合集M\",\"type\":1,\"description\":\"d\",\"tags\":[\"x\"],\"assets\":[{\"key\":\"cover\",\"value\":7}],\"tankoubon_id\":\"TANK_M\",\"children\":[{\"entity_type\":\"archive\",\"entity_id\":\"a88\",\"volume_no\":1}],\"archive_count\":3,\"pagecount\":72,\"progress\":6,\"lastreadtime\":0,\"isnew\":false,\"isfavorite\":true,\"release_at\":\"\",\"created_at\":\"\",\"updated_at\":\"2024-06-02\"}"
    let t = parseTankoubon(body)
    @Expect(t.id, "TANK_M")
    @Expect(t.name, "合集M")
    @Expect(t.archiveCount, 3)
    @Expect(t.totalPages, 72)
    @Expect(t.progress, Float32(6.0))
    @Expect(t.coverArcid, "a88")
    @Expect(t.updatedAt, "2024-06-02")
}

// ===== T11: TankoubonInfo 详情扩展（description/tags/coverAssetId/createdAt 容忍两形态）=====

// 列表形态：assets 为 {"cover":N} 对象、tags 为 CSV 字符串（Tankoubon.writeJson 真实形态）。
@Test
func tankoubonListParsesCoverTagsDescription(): Unit {
    let body = "{\"filtered\":1,\"result\":[{\"tankoubon_id\":\"TANK_C\",\"title\":\"合集C\",\"description\":\"系列总集篇\",\"tags\":\"artist:某某, full color\",\"assets\":{\"cover\":42,\"backdrop\":43},\"children\":[\"a1\"],\"archive_count\":5,\"pagecount\":200,\"progress\":50,\"created_at\":\"2024-06-12 10:00:00\",\"updated_at\":\"2024-11-02 22:14:00\"}],\"total\":1}"
    let list = parseTankoubonList(body)
    @Expect(list.size, 1)
    @Expect(list[0].coverAssetId, 42)
    @Expect(list[0].description, "系列总集篇")
    @Expect(list[0].tags.size, 2)
    @Expect(list[0].tags[0], "artist:某某")
    @Expect(list[0].tags[1], "full color")
    @Expect(list[0].createdAt, "2024-06-12 10:00:00")
}

// metadata 形态：assets 为 [{key,value}] 数组、tags 为字符串数组（详情页数据同源）。
@Test
func tankoubonMetadataParsesAssetsArrayAndTagsArray(): Unit {
    let body = "{\"title\":\"合集D\",\"description\":\"d\",\"tags\":[\"artist:某某\",\"group:某社团\"],\"assets\":[{\"key\":\"cover\",\"value\":77}],\"tankoubon_id\":\"TANK_D\",\"children\":[{\"entity_type\":\"archive\",\"entity_id\":\"a1\"}],\"archive_count\":2,\"pagecount\":90,\"progress\":30,\"created_at\":\"2024-06-12\",\"updated_at\":\"2024-11-02\"}"
    let t = parseTankoubon(body)
    @Expect(t.coverAssetId, 77)
    @Expect(t.tags.size, 2)
    @Expect(t.tags[1], "group:某社团")
    @Expect(t.createdAt, "2024-06-12")
}

// 缺省容忍：assets 空对象/缺字段时 coverAssetId 为 0、tags 为空。
@Test
func tankoubonMissingAssetsAndTagsFallBack(): Unit {
    let body = "{\"result\":[{\"tankoubon_id\":\"TANK_E\",\"title\":\"\",\"assets\":{},\"children\":[]}],\"total\":1}"
    let list = parseTankoubonList(body)
    @Expect(list[0].coverAssetId, 0)
    @Expect(list[0].tags.size, 0)
    @Expect(list[0].description, "")
}

// 混合页统计：按 pageType 字符串计数，未知类型忽略。
private func pageOf(id: String, t: String): PageInfo {
    let p = PageInfo()
    p.id = id
    p.pageType = t
    return p
}

@Test
func statPagesCountsMixedPageTypes(): Unit {
    let pages = [
        pageOf("p1", "image"),
        pageOf("p2", "image"),
        pageOf("p3", "video"),
        pageOf("p4", "audio"),
        pageOf("p5", "html"),
        pageOf("p6", "unknown")
    ]
    let s = statPages(pages)
    @Expect(s.image, 2)
    @Expect(s.video, 1)
    @Expect(s.audio, 1)
    @Expect(s.html, 1)
}

@Test
func statPagesEmptyArrayIsAllZero(): Unit {
    let s = statPages([])
    @Expect(s.image, 0)
    @Expect(s.video, 0)
    @Expect(s.audio, 0)
    @Expect(s.html, 0)
}

// HomeItem 去重 key，对齐 frontend HomePageClient :290-309。
@Test
func homeItemDedupKeys(): Unit {
    let a = SearchItem()
    a.arcid = "abc123"
    let t = TankoubonInfo()
    t.id = "TANK_9"
    @Expect(HomeItem.Arc(a).key(), "archive:abc123")
    @Expect(HomeItem.Tank(t).key(), "tankoubon:TANK_9")
}

@Test
func loginPendingTotpDecode(): Unit {
    let d = JsonCodec.decode<LoginPendingTotp>(
        "{\"requiresTotp\":true,\"challengeId\":\"abc123\",\"methods\":[\"totp\",\"recovery_code\"]}")
    @Expect(d.challengeId, "abc123")
}

@Test
func archiveMetaDecodesRelativePath(): Unit {
    let json = "{\"arcid\":\"A1\",\"relative_path\":\"doujin/2024/\",\"pagecount\":1}"
    let m = parseArchiveMeta(json)
    @Expect(m.relativePath, "doujin/2024/")
}

@Test
func archiveMetaRelativePathDefaultsEmpty(): Unit {
    let m = parseArchiveMeta("{\"arcid\":\"A1\"}")
    @Expect(m.relativePath, "")
}

@Test
func sourceNamespaceParsesCompositeId(): Unit {
    @Expect(sourceNamespace("source:nhentai:12345"), "nhentai")
    @Expect(sourceNamespace("ARC123"), "")
    @Expect(sourceNamespace("source:"), "")
    @Expect(sourceNamespace(""), "")
}

// 设置区扩展 DTO：统计/账户安全/用户管理/系统设置/词云（Task 1）
// 注：仓颉多行字符串必须换行起始，行内 JSON 一律用转义双引号，与文件内既有测试一致。
@Test
func parseSettingsDtos(): Unit {
    // UserStats：envelope + camelCase data 对象
    let stats = parseUserStats(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"favoriteCount\":328,\"readCount\":542,\"totalPagesRead\":18964,\"totalArchives\":1286}}")
    @Expect(stats.favoriteCount, 328)
    @Expect(stats.totalArchives, 1286)

    // 阅读趋势数组
    let trend = parseTrendList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"date\":\"2026-07-18\",\"count\":17},{\"date\":\"2026-07-19\",\"count\":9}]}")
    @Expect(trend.size, 2)
    @Expect(trend[0].count, 17)

    // 词云：display 缺省回落 tag
    let cloud = parseCloudTags(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"tag\":\"female:swimsuit\",\"display\":\"泳装\",\"count\":24},{\"tag\":\"original\",\"count\":38}]}")
    @Expect(cloud.size, 2)
    @Expect(cloud[0].display, "泳装")
    @Expect(cloud[1].display, "original")

    // TOTP 状态
    let totp = parseTotpStatus(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"enabled\":true,\"credentialName\":\"认证器应用\",\"createdAt\":\"2026-03-18\",\"recoveryCodesRemaining\":8}}")
    @Expect(totp.enabled, true)
    @Expect(totp.recoveryCodesRemaining, 8)

    // 会话列表：裸数组形态
    let sessions = parseSessionList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"id\":11,\"name\":\"Windows · Chrome 138\",\"prefix\":\"lanlu_Kd82\",\"createdAt\":\"2026-07-12\",\"lastUsedAt\":\"2026-07-19 10:00\",\"lastUsedIp\":\"192.168.1.23\",\"current\":true}]}")
    @Expect(sessions.size, 1)
    @Expect(sessions[0].current, true)

    // 会话列表：{sessions: [...]} 包裹形态也要容忍
    let sessions2 = parseSessionList(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"sessions\":[{\"id\":12,\"name\":\"iPhone\",\"prefix\":\"lanlu_Pq19\"}]}}")
    @Expect(sessions2.size, 1)
    @Expect(sessions2[0].id, 12)

    // Token / Passkey
    let tokens = parseTokenList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"id\":3,\"name\":\"automation\",\"prefix\":\"lanlu_n3Kx\"}]}")
    @Expect(tokens[0].prefix, "lanlu_n3Kx")
    let passkeys = parsePasskeyList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"id\":7,\"name\":\"我的工作电脑\",\"credentialId\":\"9f3a21c7\",\"algorithm\":\"ES256\",\"userVerified\":true}]}")
    @Expect(passkeys[0].algorithm, "ES256")
    @Expect(passkeys[0].userVerified, true)

    // 管理用户：data.users 包裹
    let users = parseAdminUserList(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"users\":[{\"id\":1,\"username\":\"admin\",\"isAdmin\":true,\"createdAt\":\"2025-12-01\"},{\"id\":2,\"username\":\"alice\",\"isAdmin\":false,\"createdAt\":\"2026-02-14\"}]}}")
    @Expect(users.size, 2)
    @Expect(users[0].isAdmin, true)

    // 系统设置：success/data 裸包络 + description.zh
    let settings = parseSysSettings(
        "{\"success\":true,\"data\":[{\"key\":\"SERVER_NAME\",\"value\":\"兰鹿\",\"valueType\":\"string\",\"category\":\"server\",\"description\":{\"zh\":\"服务器名称\",\"en\":\"Server name\"}},{\"key\":\"MAX_CONCURRENT_JOBS\",\"value\":\"8\",\"value_type\":\"integer\",\"category\":\"performance\"}]}")
    @Expect(settings.size, 2)
    @Expect(settings[0].descriptionZh, "服务器名称")
    @Expect(settings[1].valueType, "integer")

    // 创建用户返回的生成密码
    @Expect(parseGeneratedPassword("{\"code\":200,\"message\":\"ok\",\"data\":{\"username\":\"bob\",\"password\":\"kX3f-9Qm2\"}}"), "kX3f-9Qm2")
}

// 设置区扩展 DTO 第二批：分类/标签/智能分类/任务记录/cron/插件（Task 2）
// 注：仓颉不支持行内多行字符串，行内 JSON 一律用转义双引号，与上文 Task 1 测试一致。
@Test
func parseSettingsAdminDtos(): Unit {
    // 管理分类：蛇形键 + plugins 数组
    let cats = parseAdminCategoryList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"id\":1,\"catid\":\"doujin\",\"name\":\"同人志\",\"scan_path\":\"/library/doujinshi\",\"description\":\"CM 扫本\",\"sort_order\":0,\"enabled\":true,\"plugins\":[\"ehmeta\",\"bzmeta\"],\"cover_asset_id\":42,\"archive_count\":486}]}")
    @Expect(cats.size, 1)
    @Expect(cats[0].scanPath, "/library/doujinshi")
    @Expect(cats[0].plugins.size, 2)
    @Expect(cats[0].archiveCount, 486)

    // 标签分页：translations 展平
    let page = parseTagListPage(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"items\":[{\"id\":9,\"namespace\":\"artist\",\"name\":\"alpha\",\"translations\":{\"zh\":{\"text\":\"阿尔法\"},\"en\":{\"text\":\"alpha\"}},\"links\":\"https://x\"}],\"total\":342,\"limit\":20,\"offset\":0}}")
    @Expect(page.total, 342)
    @Expect(page.items[0].zhText, "阿尔法")

    // 智能分类：data.items 包裹
    let filters = parseSmartFilterList(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"items\":[{\"id\":1,\"name\":\"本周新增\",\"icon\":\"BookOpen\",\"query\":\"\",\"sort_by\":\"created_at\",\"sort_order\":\"desc\",\"date_from\":\"-7\",\"date_to\":\"\",\"newonly\":false,\"untaggedonly\":false,\"sort_order_num\":0,\"enabled\":true}]}}")
    @Expect(filters.size, 1)
    @Expect(filters[0].sortBy, "created_at")
    @Expect(filters[0].enabled, true)

    // 任务列表：SSE data 帧（裸 JSON，无 envelope）
    let tp = parseTaskListPage(
        "{\"tasks\":[{\"id\":1284,\"name\":\"扫描分类「同人志」\",\"status\":\"running\",\"progress\":62,\"message\":\"已处理 301/486\",\"taskType\":\"scan_category\",\"priority\":10,\"createdAt\":\"10:21:58\",\"triggerSource\":\"手动\"}],\"total\":128}")
    @Expect(tp.total, 128)
    @Expect(tp.tasks[0].status, "running")
    @Expect(tp.tasks[0].progress, 62)

    // cron 状态 / 任务 / 类型 / 校验
    let st = parseCronStatus(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"running\":true,\"totalTasks\":4,\"enabledTasks\":3}}")
    @Expect(st.running, true)
    @Expect(st.enabledTasks, 3)
    let ct = parseCronTaskList(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"tasks\":[{\"id\":1,\"name\":\"每日全库扫描\",\"cronExpression\":\"0 2 * * *\",\"taskType\":\"scan_all_categories\",\"taskParameters\":\"{}\",\"enabled\":true,\"priority\":50,\"timeoutSeconds\":3600,\"runCount\":46,\"lastRunAt\":\"2026-07-19 02:00\",\"lastRunSuccess\":true,\"nextRunAt\":\"2026-07-20 02:00\"}],\"total\":1}}")
    @Expect(ct.size, 1)
    @Expect(ct[0].hasLastRun, true)
    @Expect(ct[0].lastRunSuccess, true)
    @Expect(ct[0].taskParameters, "{}")
    let objectParams = parseCronTaskList(
        "{\"code\":200,\"data\":{\"tasks\":[{\"id\":2,\"taskParameters\":{\"category\":\"books\"}}]}}")
    @Expect(objectParams[0].taskParameters, "{\"category\":\"books\"}")
    let types = parseCronTaskTypes(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"types\":[{\"value\":\"scan_all_categories\",\"label\":\"扫描所有分类\",\"description\":\"扫描所有启用的分类\"}]}}")
    @Expect(types[0].value, "scan_all_categories")
    let vr = parseCronValidate(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"valid\":true,\"error\":\"\",\"nextRuns\":[\"2026-07-20 02:00:00\"]}}")
    @Expect(vr.valid, true)
    @Expect(vr.nextRuns.size, 1)

    // 插件：data 裸数组；参数数组
    let plugins = parsePluginList(
        "{\"code\":200,\"message\":\"ok\",\"data\":[{\"name\":\"EhMeta\",\"namespace\":\"ehmeta\",\"version\":\"1.4.2\",\"plugin_type\":\"metadata\",\"author\":\"lanlup\",\"description\":\"E站元数据\",\"enabled\":true,\"installed\":true,\"update_url\":\"https://x\",\"has_schema\":true}]}")
    @Expect(plugins.size, 1)
    @Expect(plugins[0].pluginType, "metadata")
    @Expect(plugins[0].hasSchema, true)
    let params = parsePluginParams(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"parameters\":[{\"name\":\"interval\",\"type\":\"int\",\"desc\":\"请求间隔\",\"default_value\":\"3\",\"value\":\"5\"}]}}")
    @Expect(params[0].`type`, "int")
    @Expect(params[0].value, "5")
}

@Test
func parseCreatedTokenShape(): Unit {
    let t = parseCreatedToken(
        "{\"code\":201,\"message\":\"ok\",\"data\":{\"id\":1,\"name\":\"automation\",\"prefix\":\"lanlu_n3Kx\",\"token\":\"lanlu_n3Kx9dQp2mR8vL1s\"}}")
    @Expect(t.id, 1)
    @Expect(t.prefix, "lanlu_n3Kx")
    @Expect(t.token, "lanlu_n3Kx9dQp2mR8vL1s")
}

@Test
func loginDataFromMeShape(): Unit {
    // /api/auth/me 的 dataRaw 形态：{"user":{...}}（UserDataView），直接解 LoginData。
    let d = JsonCodec.decode<LoginData>("{\"user\":{\"id\":2,\"username\":\"testtest\",\"isAdmin\":true}}")
    @Expect(d.userId, 2)
    @Expect(d.username, "testtest")
    @Expect(d.isAdmin, true)
    @Expect(d.token, "")
}

@Test
func parseRealServerShapes(): Unit {
    // 插件列表：裸 JSON 数组（无包络），plugin_type 大写转小写
    let plugins = parsePluginList(
        "[{\"name\":\"Bangumi\",\"namespace\":\"btvmeta\",\"plugin_type\":\"Metadata\",\"version\":\"1.0\",\"enabled\":true,\"installed\":true}]")
    @Expect(plugins.size, 1)
    @Expect(plugins[0].pluginType, "metadata")

    // 词云：data 为 {"items": [...], "total": N}
    let cloud = parseCloudTags(
        "{\"code\":200,\"message\":\"ok\",\"data\":{\"items\":[{\"tag\":\"original\",\"display\":\"原创\",\"count\":38}],\"total\":1}}")
    @Expect(cloud.size, 1)
    @Expect(cloud[0].display, "原创")

    // 任务快照：外层 {"v":2,"event_type":"snapshot","data":{...}} 嵌套 + 蛇形键
    let tp = parseTaskListPage(
        "{\"v\":2,\"event_type\":\"snapshot\",\"data\":{\"tasks\":[{\"id\":1284,\"name\":\"扫描分类\",\"task_type\":\"scan_category\",\"status\":\"running\",\"progress\":62,\"trigger_source\":\"手动\",\"created_at\":\"10:21:58\"}],\"total\":52334}}")
    @Expect(tp.total, 52334)
    @Expect(tp.tasks.size, 1)
    @Expect(tp.tasks[0].taskType, "scan_category")
    @Expect(tp.tasks[0].triggerSource, "手动")
    @Expect(tp.tasks[0].createdAt, "10:21:58")
}
