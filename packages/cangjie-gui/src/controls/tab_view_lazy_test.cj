package cui.controls

import std.collection.ArrayList
import lbase.{Rect}
import cui.base.{MouseButton, Renderer, UiEvent}
import cui.core.{Button, Spacer, State, StateStore, Theme, UiContext, Widget, buildRoot, rememberState}

private func lazyTabTestContext(): UiContext {
    UiContext(Renderer.headless(), Theme.light())
}

/*
 * #28: the lazy TabView (`page!: (Int64) -> Unit`) invokes the page builder ONLY for the
 * active tab — hidden pages cost no build, and since they never register focus stops there
 * is nothing to unregister per frame.
 */
@Test
func lazyTabViewBuildsOnlyTheActivePage(): Unit {
    let store = StateStore()
    let selected = State<Int64>(0)
    let built = ArrayList<Int64>()
    let build = {
        =>
        let _ = buildRoot({
            =>
            let _ = TabView(["一", "二", "三"], selected) {
                i =>
                built.add(i)
                Button("页${i}", {=> ()}).key("lazy.p${i}")
            }
        }, store)
    }
    build()
    build()
    @Expect(built.size, 2) // 每帧重建，但两帧都只构建了活动页 0
    @Expect(built[0], Int64(0))
    @Expect(built[1], Int64(0))

    // 焦点环：页签条 + 活动页的按钮；隐藏页从未注册，无需逐个注销。
    let ring = store.focusRing()
    @Expect(ring.size, 2)
    @Expect(ring[1], "lazy.p0")

    selected.value = 2
    build()
    @Expect(built.size, 3)
    @Expect(built[2], Int64(2)) // 切页后的重建才构建新页；页 1 始终未被构建
    let ringAfter = store.focusRing()
    @Expect(ringAfter.size, 2)
    @Expect(ringAfter[1], "lazy.p2")
}

/*
 * Each lazy page builds inside its own keyed scope, so same-named rememberState in two pages
 * never collides and never bleeds across tabs, and an active page's state is created once and
 * retained across rebuilds.
 */
@Test
func lazyTabViewScopesPageStatePerTab(): Unit {
    let store = StateStore()
    let selected = State<Int64>(0)
    let created = ArrayList<Int64>()
    let observed = ArrayList<String>()
    let build = {
        =>
        let _ = buildRoot({
            =>
            let _ = TabView(["A", "B"], selected) {
                i =>
                let probe = rememberState<String>("probe") {
                    created.add(i)
                    "page${i}"
                }
                observed.add(probe.value)
                Spacer()
            }
        }, store)
    }
    build()
    build()
    @Expect(created.size, 1) // 活动页的 localState 跨重建保留（只创建一次）
    @Expect(observed[observed.size - 1], "page0")

    selected.value = 1
    build()
    @Expect(observed[observed.size - 1], "page1") //  keyed scope 隔离：不是页 0 的值
}

/*
 * Strip interaction is shared with the eager init: a click moves the selection, and the
 * incoming page is built (and registered) on the next rebuild.
 */
@Test
func lazyTabViewClickSwitchesTabAndBuildsIncomingPage(): Unit {
    let ctx = lazyTabTestContext()
    let store = StateStore()
    let selected = State<Int64>(0)
    let captured = State<?Widget>(None)
    let build = {
        =>
        let _ = buildRoot({
            =>
            captured.value = Some(TabView(["A", "B"], selected) {
                i =>
                Button("P${i}", {=> ()}).key("lazy.p${i}")
            })
        }, store)
    }
    build()
    let tabs = captured.value.getOrThrow()
    tabs.layout(ctx, Rect(0.0, 0.0, 200.0, 150.0))
    @Expect(tabs.handle(ctx, UiEvent.MouseDown(MouseButton.Left, 150.0, 12.0)))
    @Expect(selected.value, Int64(1))

    build() // 新页在切换后的下一次重建中构建
    let ring = store.focusRing()
    @Expect(ring.size, 2)
    @Expect(ring[1], "lazy.p1")
}

/*
 * Empty labels: no phantom page — clampIndex would otherwise collapse the active index to 0
 * and invoke the builder for a tab that does not exist. Only the strip focus stop registers.
 */
@Test
func lazyTabViewEmptyLabelsBuildsNoPage(): Unit {
    let store = StateStore()
    let selected = State<Int64>(0)
    let built = ArrayList<Int64>()
    let build = {
        =>
        let _ = buildRoot({
            =>
            let _ = TabView(Array<String>(), selected) {
                i =>
                built.add(i)
                Spacer()
            }
        }, store)
    }
    build()
    build()
    @Expect(built.size, 0)
    @Expect(store.focusRing().size, 1) // 只剩页签条
}
