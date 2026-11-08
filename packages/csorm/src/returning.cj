package csorm

import std.collection.*

/**
 * 写操作执行结果。RETURNING 子句的原始行存入 returningRows，由调用方按需映射为 Model。
 * lastInsertId 仅在 RETURNING 单列时填充(取首行首列)。
 */
public struct InsertResult {
    public let rowsAffected: Int64
    public let lastInsertId: ?Int64
    public let returningRows: Array<Row>
    public init(rowsAffected: Int64, lastInsertId: ?Int64, returningRows: Array<Row>) {
        this.rowsAffected = rowsAffected
        this.lastInsertId = lastInsertId
        this.returningRows = returningRows
    }
}

public struct UpdateResult {
    public let rowsAffected: Int64
    public let returningRows: Array<Row>
    public init(rowsAffected: Int64, returningRows: Array<Row>) {
        this.rowsAffected = rowsAffected
        this.returningRows = returningRows
    }
}

public struct DeleteResult {
    public let rowsAffected: Int64
    public let returningRows: Array<Row>
    public init(rowsAffected: Int64, returningRows: Array<Row>) {
        this.rowsAffected = rowsAffected
        this.returningRows = returningRows
    }
}