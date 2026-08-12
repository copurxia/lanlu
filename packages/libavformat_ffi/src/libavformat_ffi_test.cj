package libavformat_ffi

private let MIXED_FIXTURE = "testdata/mixed.mkv"
private let MOV_TEXT_FIXTURE = "testdata/mov_text.mp4"

@Test
func runtimeVersionMatchesCompiledMajor(): Unit {
    ensureCompatibleLibavRuntime()
    let (formatRuntime, codecRuntime, formatCompiled, codecCompiled) = libavVersions()
    @Expect(formatRuntime >> 16, formatCompiled >> 16)
    @Expect(codecRuntime >> 16, codecCompiled >> 16)
}

@Test
func probesAllSubtitleStreamsAndMetadata(): Unit {
    let streams = probeSubtitleStreams(MIXED_FIXTURE)
    @Expect(streams.size, 3)
    @Expect(streams[0].codecName, "ass")
    @Expect(streams[0].title, "Styled English")
    @Expect(streams[0].language, "eng")
    @Expect(streams[0].isDefault)
    @Expect(streams[0].supported)
    @Expect(streams[1].codecName, "subrip")
    @Expect(streams[1].title, "Plain Chinese")
    @Expect(streams[1].language, "zho")
    @Expect(streams[1].supported)
    @Expect(streams[2].codecName, "webvtt")
    @Expect(streams[2].supported)
}

@Test
func extractsAssAndSubRipInOneScan(): Unit {
    let tracks = extractSubtitleTracks(MIXED_FIXTURE)
    @Expect(tracks.size, 3)
    @Expect(tracks[0].codecName, "ass")
    @Expect(tracks[0].codecPrivate.size > 0)
    @Expect(tracks[0].events.size, 1)
    @Expect(isMatroskaChunk(tracks[0].events[0].payloadKind))
    @Expect(tracks[1].codecName, "subrip")
    @Expect(tracks[1].events.size, 2)
    @Expect(isPlainText(tracks[1].events[0].payloadKind))
    @Expect(tracks[2].codecName, "webvtt")
    @Expect(tracks[2].events.size, 2)
}

@Test
func decodesMovTextIntoPlainEvents(): Unit {
    let tracks = extractSubtitleTracks(MOV_TEXT_FIXTURE)
    @Expect(tracks.size, 1)
    @Expect(tracks[0].codecName, "mov_text")
    @Expect(tracks[0].events.size, 2)
    @Expect(String.fromUtf8(tracks[0].events[0].payload), "Hello SRT")
}

@Test
func rejectsMissingMediaWithoutLeakingNativeResult(): Unit {
    @ExpectThrows[SubtitleNativeException](probeSubtitleStreams("testdata/not-found.mkv"))
    @ExpectThrows[SubtitleNativeException](extractSubtitleTracks("testdata/not-found.mkv"))
}

@Test
func cancellationTokenOwnsAndReleasesNativeState(): Unit {
    let token = SubtitleCancelToken()
    token.cancel()
    @ExpectThrows[SubtitleNativeException](extractSubtitleTracks(MIXED_FIXTURE, cancel: token))
    token.close()
    @Expect(token.isClosed())
    token.close()
}

@Test
func cacheEncodingRoundTripsAndRejectsCorruption(): Unit {
    let tracks = extractSubtitleTracks(MIXED_FIXTURE)
    let encoded = encodeSubtitleTracks(tracks)
    let decoded = decodeSubtitleTracks(encoded)
    @Expect(decoded.size, 3)
    @Expect(decoded[0].codecName, "ass")
    @Expect(decoded[0].codecPrivate, tracks[0].codecPrivate)
    @Expect(decoded[1].events.size, 2)
    @Expect(decoded[1].events[0].startMs, tracks[1].events[0].startMs)
    encoded[8] = encoded[8] ^ 0x40u8
    @ExpectThrows[SubtitleNativeException](decodeSubtitleTracks(encoded))
    @ExpectThrows[SubtitleNativeException](decodeSubtitleTracks(encoded[..12]))
}

private func isMatroskaChunk(kind: SubtitlePayloadKind): Bool {
    match (kind) {
        case SubtitlePayloadKind.MatroskaAssChunk => true
        case _ => false
    }
}

private func isPlainText(kind: SubtitlePayloadKind): Bool {
    match (kind) {
        case SubtitlePayloadKind.PlainText => true
        case _ => false
    }
}
