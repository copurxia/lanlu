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
    let body = "{\"motd\":\"hello\",\"name\":\"lanlu\",\"total_archives\":57,\"total_pages_read\":1234,\"version\":\"1.2.3\",\"version_desc\":\"desc\",\"version_name\":\"Cangjie\",\"db_extensions\":[]}"
    let info = JsonCodec.decode<ServerInfo>(unwrapDataRaw(body))
    @Expect(info.name, "lanlu")
    @Expect(info.version, "1.2.3")
    @Expect(info.totalArchives, 57)
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
