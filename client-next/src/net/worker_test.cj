package lanlu_client_next.net

import std.collection.ArrayList

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

@Test
func taggedTasksCanSupersedeAnotherTag(): Unit {
    let w = ApiWorker()
    @Expect(w.submitTagged("localized", "zh", {=> sleep(Duration.millisecond * 100); 1}), true)
    @Expect(w.submitTagged("localized", "en", {=> 2}), true)
    @Expect(w.submitTagged("localized", "en", {=> 3}), false)
}

@Test
func imagePoolDoesNotBlockApiPool(): Unit {
    // 图片池 4 线程全部被慢任务占满时，API 池任务仍应先行完成（两池互不阻塞）。
    let w = ApiWorker()
    for (i in 0..4) {
        @Expect(w.submitImage("img${i}", {=> sleep(Duration.millisecond * 500); i }), true)
    }
    @Expect(w.submit("fast", {=> 42 }), true)
    let order = ArrayList<String>()
    var tries = 0
    while (order.size < 5 && tries < 200) {
        for (r in w.drain()) {
            order.add(r.name)
        }
        if (order.size < 5) {
            sleep(Duration.millisecond * 20)
        }
        tries++
    }
    @Expect(order.size, 5)
    @Expect(order[0], "fast") // 慢图片任务在途期间 API 任务先到货
}

@Test
func submitImageDeduplicatesInflightName(): Unit {
    let w = ApiWorker()
    @Expect(w.submitImage("img:same", {=> sleep(Duration.millisecond * 300); 1 }), true)
    @Expect(w.submitImage("img:same", {=> 2 }), false) // 在途重名被拒
    // submit 与 submitImage 共享 inflight 命名空间：同名跨池也被拒
    @Expect(w.submit("img:same", {=> 3 }), false)
}
