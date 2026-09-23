package lanlu_client_next.net

@Test
func archiveUploadExtensionValidationCoversRegularAndSplitArchives(): Unit {
    @Expect(isSupportedArchiveUpload("book.CBZ"))
    @Expect(isSupportedArchiveUpload("book.7z.001"))
    @Expect(isSupportedArchiveUpload("book.part01.rar"))
    @Expect(isSupportedArchiveUpload("book.z01"))
    @Expect(!isSupportedArchiveUpload("cover.jpg"))
}

@Test
func uploadTaskSnapshotParsesTaskDetail(): Unit {
    let task = parseUploadTaskSnapshot(
        "{\"id\":18,\"status\":\"running\",\"progress\":42,\"message\":\"uploading\",\"result\":\"{\\\"process_task_id\\\":19}\"}")
    @Expect(task.id, 18)
    @Expect(task.status, "running")
    @Expect(task.progress, 42)
    @Expect(uploadResultTaskId(task.result, "process_task_id"), 19)
}

@Test
func uploadResultTaskIdAcceptsStringAndRejectsInvalidValues(): Unit {
    @Expect(uploadResultTaskId("{\"consume_task_id\":\"23\"}", "consume_task_id"), 23)
    @Expect(uploadResultTaskId("{\"consume_task_id\":null}", "consume_task_id"), 0)
    @Expect(uploadResultTaskId("not-json", "consume_task_id"), 0)
}

@Test
func apiMutationResultParsesRawTankoubonResponse(): Unit {
    let result = parseApiMutationResult(
        "{\"operation\":\"create_tankoubon\",\"success\":1,\"tankoubon_id\":\"TANK_42\"}", valueField: "tankoubon_id")
    @Expect(result.success)
    @Expect(result.value, "TANK_42")
    @Expect(result.error, "")
}

@Test
func apiMutationResultPreservesBusinessFailure(): Unit {
    let result = parseApiMutationResult(
        "{\"operation\":\"add_to_tankoubon\",\"success\":0,\"error\":\"Tankoubon not found\"}")
    @Expect(!result.success)
    @Expect(result.error, "Tankoubon not found")
}

@Test
func apiMutationResultAcceptsEnvelopeForCompatibility(): Unit {
    let result = parseApiMutationResult("{\"code\":200,\"data\":{\"success\":true,\"tankoubon_id\":\"TANK_E\"}}",
        valueField: "tankoubon_id")
    @Expect(result.success)
    @Expect(result.value, "TANK_E")
}
