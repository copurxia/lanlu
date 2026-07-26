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
