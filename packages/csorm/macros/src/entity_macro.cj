macro package csorm_macros

import std.ast.*
import std.collection.*
import std.convert.*

// ===== 工具 =====

func trim(s: String): String {
    let a = s.toArray()
    var i = 0
    var j = a.size
    while (i < j && a[i] == 32u8) { i += 1 }
    while (j > i && a[j - 1] == 32u8) { j -= 1 }
    String.fromUtf8(a[i..j])
}

func unquote(s: String): String {
    let a = s.toArray()
    if (a.size >= 2 && a[0] == 34u8 && a[a.size - 1] == 34u8) {
        return s[1..s.size - 1]
    }
    return s
}

func splitTop(s: String): Array<String> {
    let out = ArrayList<String>()
    let buf = ArrayList<UInt8>()
    var inq = false
    for (ch in s.toArray()) {
        if (ch == 34u8) {
            inq = !inq
            buf.add(ch)
        } else if (ch == 44u8 && !inq) {
            out.add(String.fromUtf8(buf.toArray()))
            buf.clear()
        } else {
            buf.add(ch)
        }
    }
    out.add(String.fromUtf8(buf.toArray()))
    out.toArray()
}

func indexOfEq(s: String): Int64 {
    let a = s.toArray()
    for (i in 0..a.size) {
        if (a[i] == 61u8) { return i }
    }
    return -1
}

func indexOfByte(s: String, b: UInt8): Int64 {
    let a = s.toArray()
    for (i in 0..a.size) {
        if (a[i] == b) { return i }
    }
    return -1
}

func lastIndexOfByte(s: String, b: UInt8): Int64 {
    let a = s.toArray()
    var i = a.size - 1
    while (i >= 0) {
        if (a[i] == b) { return i }
        i -= 1
    }
    return -1
}

// 字段元数据(宏展开期内部聚合)。
class ColMeta {
    var field = ""        // 仓颉字段名
    var ty = ""           // 仓颉类型文本
    var column = ""       // DB 列名(默认 = field)
    var isPk = false
    var autoInc = false   // 自增主键
    var jsonb = false     // JSONB 列(走 getJson / VJson)
    var nullable = false  // 是否为 ?T
    var elemType = ""     // 数组元素类型(Array<T> 时记录 T)
    var readonly = false  // 只读列(读 fromRow，但不参与 INSERT/UPDATE，如 GENERATED 列)
}

// 仓颉类型 → csorm ColType 枚举值(用于 rowToValue / fromRow)。
func colTypeOf(cm: ColMeta): String {
    if (cm.jsonb) { return "ColType.TJson" }
    if (cm.ty == "Array<UInt8>") { return "ColType.TBytes" }
    if (cm.elemType == "String") { return "ColType.TTextArray" }
    if (cm.elemType == "Int64") { return "ColType.TInt64Array" }
    if (cm.elemType == "Int32") { return "ColType.TInt32Array" }
    if (cm.ty == "Int64" || cm.ty == "Int32" || cm.ty == "UInt64" || cm.ty == "UInt32") { return "ColType.TInt" }
    if (cm.ty == "Float64" || cm.ty == "Float32") { return "ColType.TFloat" }
    if (cm.ty == "Bool") { return "ColType.TBool" }
    return "ColType.TText" // String / ?String 默认文本
}

// 仓颉类型 → Row 读取方法名。
func rowGetter(cm: ColMeta): String {
    if (cm.jsonb) { return "getJson" }
    if (cm.ty == "Array<UInt8>") { return "getBytes" }
    if (cm.elemType == "String") { return "getTextArray" }
    if (cm.elemType == "Int64") { return "getInt64Array" }
    if (cm.elemType == "Int32") { return "getInt32Array" }
    if (cm.ty == "Int64" || cm.ty == "Int32" || cm.ty == "UInt64" || cm.ty == "UInt32") { return "getInt64" }
    if (cm.ty == "Float64" || cm.ty == "Float32") { return "getFloat64" }
    if (cm.ty == "Bool") { return "getBool" }
    return "getText"
}

// 仓颉类型 → 可空版本的 Row 读取方法名(getOrNull*)。
func rowGetterNullable(cm: ColMeta): String {
    if (cm.jsonb) { return "getOrNullJson" }
    if (cm.ty == "Array<UInt8>") { return "getOrNullBytes" }
    if (cm.elemType == "String") { return "getTextArray" } // 数组无 OrNull 版本
    if (cm.elemType == "Int64") { return "getInt64Array" }
    if (cm.elemType == "Int32") { return "getInt32Array" }
    if (cm.ty == "Int64" || cm.ty == "Int32" || cm.ty == "UInt64" || cm.ty == "UInt32") { return "getOrNullInt64" }
    if (cm.ty == "Float64" || cm.ty == "Float32") { return "getOrNullFloat64" }
    if (cm.ty == "Bool") { return "getOrNullBool" }
    return "getOrNullText"
}

// 仓颉类型 → csorm Value 构造器。
func valueCtor(cm: ColMeta): String {
    if (cm.jsonb) { return "Value.VJson" }
    if (cm.ty == "Array<UInt8>") { return "Value.VBytes" }
    if (cm.elemType != "") {
        // 数组：构造 Array<Value> 后包成 VArr
        return "Value.VArr"
    }
    if (cm.ty == "Int64" || cm.ty == "Int32" || cm.ty == "UInt64" || cm.ty == "UInt32") { return "Value.VInt" }
    if (cm.ty == "Float64" || cm.ty == "Float32") { return "Value.VFloat" }
    if (cm.ty == "Bool") { return "Value.VBool" }
    return "Value.VText"
}

// 是否需要类型转换(如 Int32 字段需 Int32(r.getInt64(...)))。
func needsInt32Cast(cm: ColMeta): Bool {
    cm.ty == "Int32" || cm.ty == "UInt32" || cm.elemType == "Int32"
}
func needsFloat32Cast(cm: ColMeta): Bool { cm.ty == "Float32" }

// 生成 fromRow 读取单个字段的表达式 token(含末尾分号)。
func genFromRowExpr(cm: ColMeta): Tokens {
    let fTok = Token(TokenKind.IDENTIFIER, cm.field)
    let colLit = cm.column
    let semi = cangjieLex(";")
    if (cm.nullable) {
        // 可空数组：?Array<T> → isNull ? None : Some(r.getXxxArray(...))
        if (cm.elemType != "") {
            let getter = Token(TokenKind.IDENTIFIER, rowGetter(cm)) // getTextArray/getInt64Array/getInt32Array
            if (needsInt32Cast(cm)) {
                return quote(__e.$(fTok) = if (r.isNull($(colLit))) { None } else {
                    Some(Array<Int32>(r.$(getter)($(colLit)).size, { __i =>
                        Int32(r.$(getter)($(colLit))[__i]) })) }$(semi))
            }
            return quote(__e.$(fTok) = if (r.isNull($(colLit))) { None } else {
                Some(r.$(getter)($(colLit))) }$(semi))
        }
        let getter = Token(TokenKind.IDENTIFIER, rowGetterNullable(cm))
        if (needsInt32Cast(cm)) {
            return quote(__e.$(fTok) = if (r.isNull($(colLit))) { None } else {
                match (r.$(getter)($(colLit))) { case Some(__v) => Some(Int32(__v)); case None => None } }$(semi))
        }
        if (needsFloat32Cast(cm)) {
            return quote(__e.$(fTok) = if (r.isNull($(colLit))) { None } else {
                match (r.$(getter)($(colLit))) { case Some(__v) => Some(Float32(__v)); case None => None } }$(semi))
        }
        return quote(__e.$(fTok) = if (r.isNull($(colLit))) { None } else { r.$(getter)($(colLit)) }$(semi))
    }
    let getter = Token(TokenKind.IDENTIFIER, rowGetter(cm))
    if (needsInt32Cast(cm)) {
        return quote(__e.$(fTok) = Int32(r.$(getter)($(colLit)))$(semi))
    }
    if (needsFloat32Cast(cm)) {
        return quote(__e.$(fTok) = Float32(r.$(getter)($(colLit)))$(semi))
    }
    return quote(__e.$(fTok) = r.$(getter)($(colLit))$(semi))
}

// 字段宏：@[pk] 标记主键。属性 attr 可为空或 "auto"。
public macro pk(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[pk] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("type", vd.declType.toTokens().toString())
    setItem("isPk", "true")
    let a = trim(attr.toString())
    setItem("autoInc", if (a == "auto") { "true" } else { "false" })
    return input
}

// 字段宏：@[jsonb] 标记 JSONB 文本列。
public macro jsonb(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[jsonb] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("type", vd.declType.toTokens().toString())
    setItem("jsonb", "true")
    return input
}

// 字段宏：@[column[name = "db_col"]] 指定 DB 列名(默认 = 字段名)。
public macro column(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[column] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("type", vd.declType.toTokens().toString())
    // 解析 name = "xxx"
    var colName = vd.identifier.value
    for (seg0 in splitTop(attr.toString())) {
        let seg = trim(seg0)
        if (seg == "") { continue }
        let eq = indexOfEq(seg)
        if (eq > 0) {
            let key = trim(seg[0..eq])
            let val = unquote(trim(seg[eq + 1..seg.size]))
            if (key == "name") { colName = val }
        }
    }
    setItem("column", colName)
    return input
}

// 字段宏：@[readonly] 只读列(读 fromRow，但不参与 INSERT/UPDATE，如 GENERATED 列)。
public macro readonly(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[readonly] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("type", vd.declType.toTokens().toString())
    setItem("readonly", "true")
    return input
}

/**
 * 字段宏：@[hasMany[target = "RelChild", to = "parent_id"]]
 * 标记一对多关系：当前实体的 pk ← 目标实体的 toCol。
 * 属性：target = "目标 struct 名"(必填)，to = "外键列名"(必填)。
 * 该字段本身不参与 INSERT/UPDATE(视为关系标记，非真实列)。
 */
public macro hasMany(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[hasMany] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("relType", "HasMany")
    // 解析 target = "..." 和 to = "..."
    var target = ""
    var toCol = ""
    for (seg0 in splitTop(attr.toString())) {
        let seg = trim(seg0)
        if (seg == "") { continue }
        let eq = indexOfEq(seg)
        if (eq > 0) {
            let key = trim(seg[0..eq])
            let val = unquote(trim(seg[eq + 1..seg.size]))
            if (key == "target") { target = val }
            else if (key == "to") { toCol = val }
        }
    }
    if (target == "") {
        throw Exception("@[hasMany] 缺少 target 属性")
    }
    if (toCol == "") {
        throw Exception("@[hasMany] 缺少 to 属性(外键列名)")
    }
    setItem("relTarget", target)
    setItem("relToCol", toCol)
    return input
}

/**
 * 字段宏：@[hasOne[target = "RelProfile", to = "user_id"]]
 * 标记一对一关系。属性同 @[hasMany]。
 */
public macro hasOne(attr: Tokens, input: Tokens): Tokens {
    if (!insideParentContext("entity")) {
        throw Exception("@[hasOne] 只能用于 @entity 修饰的 struct 字段")
    }
    let vd = (parseDecl(input) as VarDecl).getOrThrow()
    setItem("field", vd.identifier.value)
    setItem("relType", "HasOne")
    var target = ""
    var toCol = ""
    for (seg0 in splitTop(attr.toString())) {
        let seg = trim(seg0)
        if (seg == "") { continue }
        let eq = indexOfEq(seg)
        if (eq > 0) {
            let key = trim(seg[0..eq])
            let val = unquote(trim(seg[eq + 1..seg.size]))
            if (key == "target") { target = val }
            else if (key == "to") { toCol = val }
        }
    }
    if (target == "") {
        throw Exception("@[hasOne] 缺少 target 属性")
    }
    if (toCol == "") {
        throw Exception("@[hasOne] 缺少 to 属性(外键列名)")
    }
    setItem("relTarget", target)
    setItem("relToCol", toCol)
    return input
}

/**
 * @entity 属性宏：作用于 struct，生成 Entity/ActiveModel 实现类 + 工厂函数。
 * 用法：
 *   @Entity[table = "users"]
 *   public struct User {
 *     @[pk auto]
 *     id: Int64
 *     name: String
 *     age: Int64
 *     bio: ?String
 *     meta: String        // JSONB
 *     tags: Array<String>
 *   }
 * 属性选项：table = "表名"(必填)，schema = "public"(可选)。
 * 字段：@[pk] 主键(可加 auto 表自增)，@[jsonb] JSONB 列；其余字段按类型自动映射。
 */
public macro entity(attr: Tokens, input: Tokens): Tokens {
    let decl = parseDecl(input)
    let sd = match (decl as StructDecl) {
        case Some(v) => v
        case None => throw Exception("@entity 只能修饰 struct")
    }
    let structName = sd.identifier.value
    let entityName = structName + "Entity"
    let activeName = structName + "Active"
    let entityTok = Token(TokenKind.IDENTIFIER, entityName)
    let activeTok = Token(TokenKind.IDENTIFIER, activeName)
    let structTok = Token(TokenKind.IDENTIFIER, structName)

    // 解析属性：table / schema
    var tableName = structName
    var schemaName = ""
    for (seg0 in splitTop(attr.toString())) {
        let seg = trim(seg0)
        if (seg == "") { continue }
        let eq = indexOfEq(seg)
        if (eq < 0) { continue }
        let key = trim(seg[0..eq])
        let val = unquote(trim(seg[eq + 1..seg.size]))
        if (key == "table") { tableName = val }
        else if (key == "schema") { schemaName = val }
    }

    // 收集字段：从子宏消息 + 从 struct body 直接解析(无注解的普通字段)
    let pkMsgs = getChildMessages("pk")
    let jsonbMsgs = getChildMessages("jsonb")
    let columnMsgs = getChildMessages("column")
    let readonlyMsgs = getChildMessages("readonly")
    let hasManyMsgs = getChildMessages("hasMany")
    let hasOneMsgs = getChildMessages("hasOne")
    let relationMsgs = ArrayList<MacroMessage>()
    for (m in hasManyMsgs) { relationMsgs.add(m) }
    for (m in hasOneMsgs) { relationMsgs.add(m) }
    // 关系字段名集合(这些字段不参与 INSERT/UPDATE/fromRow 列读取)
    let relationFields = HashSet<String>()
    for (m in relationMsgs) {
        relationFields.add(m.getString("field"))
    }

    // 从 struct body 提取全部字段 VarDecl(用于无注解字段)
    let bodyFields = ArrayList<ColMeta>()
    let structBody = sd.body
    // StructDecl.body 是 Body 类型，遍历 decls
    for (d in structBody.decls) {
        match (d as VarDecl) {
            case Some(vd) =>
                let cm = ColMeta()
                cm.field = vd.identifier.value
                cm.ty = vd.declType.toTokens().toString()
                cm.column = cm.field
                bodyFields.add(cm)
            case None => ()
        }
    }

    // 合并注解信息到 bodyFields
    for (cm in bodyFields) {
        // 查 pk 消息
        for (m in pkMsgs) {
            if (m.getString("field") == cm.field) {
                cm.isPk = true
                cm.autoInc = m.getString("autoInc") == "true"
            }
        }
        // 查 jsonb 消息
        for (m in jsonbMsgs) {
            if (m.getString("field") == cm.field) {
                cm.jsonb = true
            }
        }
        // 查 column 消息(显式列名)
        for (m in columnMsgs) {
            if (m.getString("field") == cm.field) {
                let cn = m.getString("column")
                if (cn != "") { cm.column = cn }
            }
        }
        // 查 readonly 消息
        for (m in readonlyMsgs) {
            if (m.getString("field") == cm.field) {
                cm.readonly = true
            }
        }
        // 解析 nullable：类型以 ? 开头
        let t = cm.ty.trimAscii()
        if (t.startsWith("?")) {
            cm.nullable = true
            cm.ty = t[1..t.size].trimAscii()
        }
        // 解析数组：Array<T> (允许类型字符串含空格，如 "Array< String >")
        let ltIdx = indexOfByte(cm.ty, 60u8)   // '<'
        if (cm.ty.startsWith("Array") && ltIdx > 0 && ltIdx < cm.ty.size - 1) {
            // 取最后一个 '>' 之间的内容
            let gtIdx = lastIndexOfByte(cm.ty, 62u8) // '>'
            if (gtIdx > ltIdx) {
                cm.elemType = cm.ty[ltIdx + 1..gtIdx].trimAscii()
            }
        }
    }

    // 校验：至少一个主键
    let pkFields = ArrayList<ColMeta>()
    for (cm in bodyFields) {
        if (cm.isPk) { pkFields.add(cm) }
    }
    if (pkFields.size == 0) {
        throw Exception("@entity ${structName} 缺少 @[pk] 主键字段")
    }
    let autoInc = pkFields[0].autoInc && pkFields.size == 1

    // ===== 生成 tokens =====
    let allCols = bodyFields

    // fromRow 时跳过关系字段(它们不是真实列)
    let allColsForFromRow = ArrayList<ColMeta>()
    for (cm in allCols) {
        if (!relationFields.contains(cm.field)) {
            allColsForFromRow.add(cm)
        }
    }

    // columns() 返回数组字面量(跳过关系字段)
    let colNames = ArrayList<String>()
    for (cm in allCols) {
        if (!relationFields.contains(cm.field)) {
            colNames.add(cm.column)
        }
    }
    let colsArrTok = Tokens()
    var firstC = true
    for (cn in colNames) {
        if (!firstC) { colsArrTok.append(Token(TokenKind.COMMA)) }
        firstC = false
        colsArrTok.append(quote($(cn)))
    }

    // pkColumns() 返回数组字面量
    let pkNames = ArrayList<String>()
    for (cm in pkFields) { pkNames.add(cm.column) }
    let pkArrTok = Tokens()
    var firstP = true
    for (cn in pkNames) {
        if (!firstP) { pkArrTok.append(Token(TokenKind.COMMA)) }
        firstP = false
        pkArrTok.append(quote($(cn)))
    }

    // fromRow 体：构造 struct 并逐字段赋值(跳过关系字段)
    let fromRowStmts = Tokens()
    fromRowStmts.append(quote(var __e = $(structTok)()))
    fromRowStmts.append(Token(TokenKind.NL))
    for (cm in allColsForFromRow) {
        fromRowStmts.append(genFromRowExpr(cm))
        fromRowStmts.append(Token(TokenKind.NL))
    }
    fromRowStmts.append(quote(return __e))

    // schema 返回
    let schemaExpr = if (schemaName == "") { quote(None) } else { quote(Some($(schemaName))) }

    // relations() 实现：为每个 @[hasOne]/@[hasMany] 生成 RelationDef
    // 用目标实体工厂函数(如 relChildEntity())取目标 Entity，构造 RelationDef.hasMany/hasOne
    let relationsStmts = Tokens()
    relationsStmts.append(quote(let __rels = ArrayList<RelationDef>()))
    relationsStmts.append(Token(TokenKind.NL))
    for (m in relationMsgs) {
        let relType = m.getString("relType")
        let targetName = m.getString("relTarget")
        let toCol = m.getString("relToCol")
        // 目标实体工厂函数名：lowerFirst(targetName) + "Entity"
        let targetFactory = lowerFirst(targetName) + "Entity"
        let targetFactoryTok = Token(TokenKind.IDENTIFIER, targetFactory)
        let toColTok = quote($(toCol))
        if (relType == "HasMany") {
            relationsStmts.append(quote(
                __rels.add(RelationDef.hasMany(this, $(targetFactoryTok)(), $(toColTok)))
            ))
        } else {
            relationsStmts.append(quote(
                __rels.add(RelationDef.hasOne(this, $(targetFactoryTok)(), $(toColTok)))
            ))
        }
        relationsStmts.append(Token(TokenKind.NL))
    }
    relationsStmts.append(quote(return __rels.toArray()))

    // columnDefs() 实现：按字段类型 + @[column] 属性派生 ColumnDef 列表。
    // 跳过关系字段(它们不是真实列)。跳过 readonly 列(GENERATED)。
    let columnDefsStmts = Tokens()
    columnDefsStmts.append(quote(let __cds = ArrayList<ColumnDef>()))
    columnDefsStmts.append(Token(TokenKind.NL))
    for (cm in allCols) {
        // 跳过关系字段与 readonly 列
        if (relationFields.contains(cm.field)) { continue }
        if (cm.readonly) { continue }
        let colNameTok = quote($(cm.column))
        let sqlColTypeTok = macroCjTypeToSqlColType(cm)
        let cdVar = Token(TokenKind.IDENTIFIER, "__cd_" + cm.field)
        columnDefsStmts.append(quote(let $(cdVar) = ColumnDef($(colNameTok), $(sqlColTypeTok))))
        columnDefsStmts.append(Token(TokenKind.NL))
        // pk + autoIncrement
        if (cm.isPk) {
            if (cm.autoInc) {
                columnDefsStmts.append(quote($(cdVar).setPk().setAutoIncrement()))
            } else {
                columnDefsStmts.append(quote($(cdVar).setPk()))
            }
            columnDefsStmts.append(Token(TokenKind.NL))
        } else {
            // 非 pk 列：nullable 取决于类型是否为 ?T
            if (!cm.nullable) {
                columnDefsStmts.append(quote($(cdVar).notNull()))
                columnDefsStmts.append(Token(TokenKind.NL))
            }
        }
        columnDefsStmts.append(quote(__cds.add($(cdVar))))
        columnDefsStmts.append(Token(TokenKind.NL))
    }
    columnDefsStmts.append(quote(return __cds.toArray()))

    // ActiveModel 字段声明：每个字段一个 var x: ActiveValue = NotSet
    let activeFields = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        activeFields.append(quote(public var $(fTok): ActiveValue = ActiveValue.NotSet))
        activeFields.append(Token(TokenKind.NL))
    }

    // ActiveModel set(col, v)：match col { "f" => self.f = Set(v); ... }
    let setCases = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        setCases.append(quote(case $(cm.field) => this.$(fTok) = ActiveValue.Set(v)))
        setCases.append(Token(TokenKind.NL))
    }
    setCases.append(quote(case _ => throw CsormError("ActiveModel: unknown column " + col)))

    // ActiveModel unset(col)
    let unsetCases = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        unsetCases.append(quote(case $(cm.field) => this.$(fTok) = ActiveValue.NotSet))
        unsetCases.append(Token(TokenKind.NL))
    }
    unsetCases.append(quote(case _ => throw CsormError("ActiveModel: unknown column " + col)))

    // ActiveModel get(col)：返回 ActiveValue
    let getCases = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        getCases.append(quote(case $(cm.field) => this.$(fTok)))
        getCases.append(Token(TokenKind.NL))
    }
    getCases.append(quote(case _ => throw CsormError("ActiveModel: unknown column " + col)))

    // ActiveModel isChanged(col)
    let isChangedCases = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        isChangedCases.append(quote(case $(cm.field) => avIsSet(this.$(fTok))))
        isChangedCases.append(Token(TokenKind.NL))
    }
    isChangedCases.append(quote(case _ => false))

    // ActiveModel getValue(col)
    let getValueCases = Tokens()
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        getValueCases.append(quote(case $(cm.field) => avValue(this.$(fTok))))
        getValueCases.append(Token(TokenKind.NL))
    }
    getValueCases.append(quote(case _ => Value.VNull))

    // ActiveModel pkValue()：返回 [pk1, pk2, ...]
    let pkValueExpr = Tokens()
    pkValueExpr.append(quote([))
    var firstPk = true
    for (cm in pkFields) {
        if (!firstPk) { pkValueExpr.append(Token(TokenKind.COMMA)) }
        firstPk = false
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        pkValueExpr.append(quote(avValue(this.$(fTok))))
    }
    pkValueExpr.append(quote(]))

    // ActiveModel setEntries()：仅 Set 列(跳过 readonly)；列名用 DB 列名(cm.column)
    let setEntriesStmts = Tokens()
    setEntriesStmts.append(quote(let __out = ArrayList<(String, Value)>()))
    for (cm in allCols) {
        if (cm.readonly) { continue }
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        setEntriesStmts.append(quote(
            if (avIsSet(this.$(fTok))) { __out.add(($(cm.column), avValue(this.$(fTok)))) }))
        setEntriesStmts.append(Token(TokenKind.NL))
    }
    setEntriesStmts.append(quote(return __out.toArray()))

    // ActiveModel setNonPkEntries()：Set 且非主键 且非 readonly
    let setNonPkStmts = Tokens()
    setNonPkStmts.append(quote(let __out = ArrayList<(String, Value)>()))
    for (cm in allCols) {
        if (cm.isPk || cm.readonly) { continue }
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        setNonPkStmts.append(quote(
            if (avIsSet(this.$(fTok))) { __out.add(($(cm.column), avValue(this.$(fTok)))) }))
        setNonPkStmts.append(Token(TokenKind.NL))
    }
    setNonPkStmts.append(quote(return __out.toArray()))

    // isAnyChanged()
    let isAnyExpr = Tokens()
    isAnyExpr.append(quote(false))
    for (cm in allCols) {
        let fTok = Token(TokenKind.IDENTIFIER, cm.field)
        isAnyExpr.append(quote(|| avIsSet(this.$(fTok))))
    }

    // emptyActive() 引用
    let emptyActiveExpr = quote($(activeTok)())

    // ===== 组装输出 =====
    let output = quote(
        $(input)

        public class $(entityTok) <: Entity {
            public init() {}
            public func table(): String { $(tableName) }
            public func schema(): ?String { $(schemaExpr) }
            public func columns(): Array<String> { [$(colsArrTok)] }
            public func pkColumns(): Array<String> { [$(pkArrTok)] }
            public func autoIncrement(): Bool { $(autoInc) }
            public func fromRow(r: Row): Any {
                $(fromRowStmts)
            }
            public func emptyActive(): ActiveModel { $(emptyActiveExpr) }
            public func relations(): Array<RelationDef> {
                $(relationsStmts)
            }
            public func columnDefs(): Array<ColumnDef> {
                $(columnDefsStmts)
            }
        }

        public class $(activeTok) <: ActiveModel {
            $(activeFields)
            public init() {}
            public func entity(): Entity { $(entityTok)() }
            public func get(col: String): ActiveValue {
                match (col) {
                    $(getCases)
                }
            }
            public func set(col: String, v: Value): Unit {
                match (col) {
                    $(setCases)
                }
            }
            public func unset(col: String): Unit {
                match (col) {
                    $(unsetCases)
                }
            }
            public func isChanged(col: String): Bool {
                match (col) {
                    $(isChangedCases)
                }
            }
            public func getValue(col: String): Value {
                match (col) {
                    $(getValueCases)
                }
            }
            public func pkValue(): Array<Value> { $(pkValueExpr) }
            public func setEntries(): Array<(String, Value)> {
                $(setEntriesStmts)
            }
            public func setNonPkEntries(): Array<(String, Value)> {
                $(setNonPkStmts)
            }
            public func isAnyChanged(): Bool { $(isAnyExpr) }
        }

        public func $(Token(TokenKind.IDENTIFIER, lowerFirst(structName) + "Entity"))(): $(entityTok) { $(entityTok)() }
    )
    return output
}

// 仓颉类型文本 → SqlColType 构造 Tokens(宏展开期使用，对标运行时 cjTypeToSqlColType)。
// 返回如 SqlColType.TInt64 / SqlColType.TText / SqlColType.TArray(SqlColType.TText) 等。
func macroCjTypeToSqlColType(cm: ColMeta): Tokens {
    let t = cm.ty.trimAscii()
    // 去掉 ?
    var base = t
    if (base.startsWith("?")) {
        base = base[1..base.size].trimAscii()
    }
    // 自增主键 → TSerial64
    if (cm.isPk && cm.autoInc) { return quote(SqlColType.TSerial64) }
    // jsonb 列 → TJsonb
    if (cm.jsonb) { return quote(SqlColType.TJsonb) }
    // 数组：Array<T> → TArray(elem)
    if (base.startsWith("Array")) {
        let lt = indexOfByte(base, 60u8)   // '<'
        let gt = lastIndexOfByte(base, 62u8) // '>'
        if (lt >= 0 && gt > lt) {
            let elemTy = base[lt + 1..gt].trimAscii()
            if (elemTy == "String") { return quote(SqlColType.TArray(SqlColType.TText)) }
            if (elemTy == "Int64") { return quote(SqlColType.TArray(SqlColType.TInt64)) }
            if (elemTy == "Int32") { return quote(SqlColType.TArray(SqlColType.TInt32)) }
            if (elemTy == "UInt8") { return quote(SqlColType.TBytes) }
            return quote(SqlColType.TArray(SqlColType.TText))
        }
    }
    // 标量类型
    if (base == "Bool") { return quote(SqlColType.TBool) }
    if (base == "Int16") { return quote(SqlColType.TInt16) }
    if (base == "Int32") { return quote(SqlColType.TInt32) }
    if (base == "Int64") { return quote(SqlColType.TInt64) }
    if (base == "UInt16") { return quote(SqlColType.TInt16) }
    if (base == "UInt32") { return quote(SqlColType.TInt32) }
    if (base == "UInt64") { return quote(SqlColType.TInt64) }
    if (base == "Float32") { return quote(SqlColType.TFloat32) }
    if (base == "Float64") { return quote(SqlColType.TFloat64) }
    if (base == "String") { return quote(SqlColType.TText) }
    if (base == "Array<UInt8>") { return quote(SqlColType.TBytes) }
    // 默认 TEXT
    return quote(SqlColType.TText)
}

// 首字母小写(用于工厂函数命名)。
func lowerFirst(s: String): String {
    let a = s.toArray()
    if (a.size == 0) { return s }
    if (a[0] >= 65u8 && a[0] <= 90u8) {
        let out = ArrayList<UInt8>()
        out.add(a[0] + 32u8)
        for (i in 1..a.size) { out.add(a[i]) }
        return String.fromUtf8(out.toArray())
    }
    s
}