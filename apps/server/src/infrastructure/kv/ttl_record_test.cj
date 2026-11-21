package lanlu.infrastructure.kv

@Test
func kvTtlRecordCodecRoundTripTest() {
    let encoded = KvTtlRecords.encode("value-1", 60)
    let decoded = KvTtlRecordCodec.decode(encoded)
    @Assert(decoded.isSome())
    if (let Some(record) <- decoded) {
        @Expect(record.value, "value-1")
        @Expect(record.ttlSeconds, 60)
        @Expect(record.createdAt > 0)
    }
}

@Test
func kvTtlRecordCodecRejectsInvalidPayloadTest() {
    @Expect(KvTtlRecordCodec.decode("").isNone())
    @Expect(KvTtlRecordCodec.decode("not-json").isNone())
}

@Test
func kvTtlRecordExpirationTest() {
    let active = KvTtlRecord("active", 0)
    @Expect(!KvTtlRecords.isExpired(active))

    let expired = KvTtlRecord()
    expired.value = "expired"
    expired.createdAt = 1
    expired.ttlSeconds = 1
    @Expect(KvTtlRecords.isExpired(expired))
}
