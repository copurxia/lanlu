package lanlu_client_next.net

@Test
func submitDeliversPayloadViaDrain(): Unit {
    let w = ApiWorker()
    @Expect(w.submit("t1", {=> 42}), true)
    var tries = 0
    var got = w.drain()
    while (got.size == 0 && tries < 100) {
        sleep(Duration.millisecond * 20)
        got = w.drain()
        tries++
    }
    @Expect(got.size, 1)
    @Expect(got[0].name, "t1")
    @Expect(got[0].error, "")
    match (got[0].payload) {
        case Some(v) => @Expect((v as Int64).getOrThrow(), 42)
        case None => @Expect(true, false)
    }
    @Expect(w.drain().size, 0)  // drain 取走后清空
}

@Test
func jobExceptionBecomesErrorResult(): Unit {
    let w = ApiWorker()
    w.submit("bad", {=> throw Exception("boom"); 0 })
    var tries = 0
    var got = w.drain()
    while (got.size == 0 && tries < 100) { sleep(Duration.millisecond * 20); got = w.drain(); tries++ }
    @Expect(got.size, 1)
    @Expect(got[0].error.contains("boom"), true)
}

@Test
func duplicateNameRejectedWhileInflight(): Unit {
    let w = ApiWorker()
    @Expect(w.submit("slow", {=> sleep(Duration.millisecond * 300); 1 }), true)
    @Expect(w.submit("slow", {=> 2 }), false)  // 在途重名被拒
}
