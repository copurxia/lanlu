package postgresql_driver

/**
 * 阶段五测试：类型化 Value(VTimestamp/VDate/VUuid/VDecimal/VEnum) + ActiveEnum + Value 转换。
 */
import csorm.*
import csorm
import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import std.collection.*
import std.time.*

func tvConnStr(): String {
    getVariable("DB_STRING") ??
        "postgres://copur:e29khrowY77mGk@192.168.0.112:5432/lanludev?sslmode=disable&pool.max=5"
}

func openTvOrSkip(): ?Database {
    try {
        return Some(Database(PgConn(tvConnStr())))
    } catch (_: Exception) {
        println("[skip] no PostgreSQL available (typed_value test)")
        return None
    }
}

// 测试 ActiveEnum：ArchiveStatus
public enum ArchiveStatus <: ActiveEnum {
    | Unread
    | Reading
    | Read
    public func enumName(): String { "archive_status" }
    public func toValue(): String {
        match (this) {
            case Unread => "unread"
            case Reading => "reading"
            case Read => "read"
        }
    }
    public func fromValue(raw: String): Bool {
        let me = this.toValue()
        me == raw
    }
}

@Test
func test_typed_value_new_variants() {
    // VTimestamp
    let ts = vtimestamp(1_700_000_000_000_000)  // epoch μs
    match (ts) {
        case Value.VTimestamp(us) => @Expect(us, 1_700_000_000_000_000)
        case _ => @Expect(true, false)
    }
    // VDate
    let d = vdate(19723)  // days from epoch
    match (d) {
        case Value.VDate(days) => @Expect(days, 19723)
        case _ => @Expect(true, false)
    }
    // VUuid
    let u = vuuid("123e4567-e89b-12d3-a456-426614174000")
    match (u) {
        case Value.VUuid(s) => @Expect(s, "123e4567-e89b-12d3-a456-426614174000")
        case _ => @Expect(true, false)
    }
    // VDecimal
    let dec = vdecimal("123.456")
    match (dec) {
        case Value.VDecimal(s) => @Expect(s, "123.456")
        case _ => @Expect(true, false)
    }
    // VEnum
    let e = venum("archive_status", "unread")
    match (e) {
        case Value.VEnum(name, raw) => @Expect(name, "archive_status"); @Expect(raw, "unread")
        case _ => @Expect(true, false)
    }
    println("[typed-value-test] new variants passed")
}

@Test
func test_typed_value_to_pg() {
    // VTimestamp → PGText(格式化文本)
    let ts = vtimestamp(1_700_000_000_000_000)
    let pg = valueToPG(ts)
    match (pg) {
        case PGValue.PGText(s) => @Expect(s.contains("2023"), true)
        case _ => @Expect(true, false)
    }
    // VUuid → PGText
    let u = vuuid("123e4567-e89b-12d3-a456-426614174000")
    match (valueToPG(u)) {
        case PGValue.PGText(s) => @Expect(s, "123e4567-e89b-12d3-a456-426614174000")
        case _ => @Expect(true, false)
    }
    // VDecimal → PGText
    match (valueToPG(vdecimal("99.99"))) {
        case PGValue.PGText(s) => @Expect(s, "99.99")
        case _ => @Expect(true, false)
    }
    // VEnum → PGText(rawValue)
    match (valueToPG(venum("archive_status", "reading"))) {
        case PGValue.PGText(s) => @Expect(s, "reading")
        case _ => @Expect(true, false)
    }
    println("[typed-value-test] valueToPG passed")
}

@Test
func test_active_enum() {
    @Expect(ArchiveStatus.Unread.toValue(), "unread")
    @Expect(ArchiveStatus.Reading.toValue(), "reading")
    @Expect(ArchiveStatus.Read.toValue(), "read")
    @Expect(ArchiveStatus.Unread.enumName(), "archive_status")
    @Expect(ArchiveStatus.Unread.fromValue("unread"), true)
    @Expect(ArchiveStatus.Reading.fromValue("unread"), false)
    // ActiveEnum → Value.VEnum
    let v = activeEnumToValue(ArchiveStatus.Read)
    match (v) {
        case Value.VEnum(name, raw) => @Expect(name, "archive_status"); @Expect(raw, "read")
        case _ => @Expect(true, false)
    }
    println("[typed-value-test] ActiveEnum passed")
}

@Test
func test_typed_value_datetime_into_value() {
    let now = DateTime.now()
    let v = now.intoValue()
    match (v) {
        case Value.VTimestamp(us) =>
            // epoch μs 应为正数
            @Expect(us > 0, true)
        case _ => @Expect(true, false)
    }
    println("[typed-value-test] DateTime.intoValue passed")
}

@Test
func test_typed_value_pg_roundtrip() {
    match (openTvOrSkip()) {
        case None => return
        case Some(db) =>
            db.execRawSql("DROP TABLE IF EXISTS csorm_tv_test")
            db.execRawSql("CREATE TABLE csorm_tv_test (id SERIAL PRIMARY KEY, ts TIMESTAMPTZ NOT NULL DEFAULT now(), uid UUID, dec NUMERIC(10,2), status TEXT)")

            // 写入：VTimestampTz、VUuid、VDecimal、VEnum
            let ins = insertQuery("csorm_tv_test")
                .columns(["ts", "uid", "dec", "status"])
                .values([
                    vtimestampTz(DateTime.now().toUnixTimeStamp().toMicroseconds()),
                    vuuid("123e4567-e89b-12d3-a456-426614174000"),
                    vdecimal("42.50"),
                    venum("archive_status", "reading")
                ])
                .returning(["id", "ts", "uid", "dec", "status"])
            let rows = db.execReturning<csorm.Row>(ins, { r => r })
            @Expect(rows.size, 1)
            let r = rows[0]
            // ts 应可读为文本
            @Expect(r.getText("ts").size > 0, true)
            @Expect(r.getText("uid"), "123e4567-e89b-12d3-a456-426614174000")
            @Expect(r.getText("dec"), "42.50")
            @Expect(r.getText("status"), "reading")

            db.execRawSql("DROP TABLE IF EXISTS csorm_tv_test")
            db.close()
            println("[typed-value-test] PG roundtrip passed")
    }
}