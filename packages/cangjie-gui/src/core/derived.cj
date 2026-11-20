package cui.core

import std.collection.ArrayList

/*
 * Derived, read-only state and two-way bindings.
 *
 * DerivedState follows the pull model that fits a per-frame rebuilt UI: reading `value`
 * recomputes only when a source revision moved, so deriving inside a view body costs one
 * closure call per frame and never registers upstream listeners. Push-style `observe`
 * subscribes to the sources only for the lifetime of the returned observation, keeping
 * source listener lists free of leaked frame-local subscribers.
 */

/** A mutable box shared between closures; works around var-capture restrictions. */
class ValueCell<T> {
    var value: T

    init(value: T) {
        this.value = value
    }
}

/**
 * A read-only observable computed from one or more sources, created with `derive` or
 * `Observable.map`. The computation is lazy and cached: it reruns only when a source
 * revision changes between reads.
 */
public class DerivedState<T> <: Observable<T> {
    private let compute: () -> T
    private let sourceRevisions: () -> Array<UInt64>
    private let subscribeSources: (() -> Unit) -> Array<() -> Unit>
    private var cachedValue: ?T = None
    private var seenRevisions: Array<UInt64> = Array<UInt64>()
    private var selfRevision: UInt64 = UInt64(0)
    // Scalar fast path for 1/2/3-source derives: revisions are read and compared without
    // allocating the revision array on every read — the common case is "nothing changed".
    private let scalarArity: Int64
    private let readScalarA: () -> UInt64
    private let readScalarB: () -> UInt64
    private let readScalarC: () -> UInt64
    private var seenA: UInt64 = UInt64(0)
    private var seenB: UInt64 = UInt64(0)
    private var seenC: UInt64 = UInt64(0)

    init(
        compute: () -> T,
        sourceRevisions: () -> Array<UInt64>,
        subscribeSources: (() -> Unit) -> Array<() -> Unit>,
        scalarArity!: Int64 = 0,
        readScalarA!: () -> UInt64 = {=> UInt64(0)},
        readScalarB!: () -> UInt64 = {=> UInt64(0)},
        readScalarC!: () -> UInt64 = {=> UInt64(0)}
    ) {
        this.compute = compute
        this.sourceRevisions = sourceRevisions
        this.subscribeSources = subscribeSources
        this.scalarArity = scalarArity
        this.readScalarA = readScalarA
        this.readScalarB = readScalarB
        this.readScalarC = readScalarC
    }

    /** The computed value, refreshed if any source changed since the last read. */
    public prop value: T {
        get() {
            refreshIfStale()
        }
    }

    public func get(): T {
        value
    }

    public prop revision: UInt64 {
        get() {
            let _ = refreshIfStale()
            selfRevision
        }
    }

    public func observe(callback: (T, T) -> Unit): StateObservation<T> {
        let previous = ValueCell<T>(value)
        let cancels = subscribeSources(
            {
                =>
                let next = value
                let before = previous.value
                previous.value = next
                callback(before, next)
            }
        )
        StateObservation<T>({=> for (cancel in cancels) { cancel() }})
    }

    private func refreshIfStale(): T {
        if (scalarArity > 0) {
            match (cachedValue) {
                case Some(cached) where !scalarRevisionsDiffer() => cached
                case _ =>
                    let fresh = compute()
                    cachedValue = Some(fresh)
                    seenA = readScalarA()
                    if (scalarArity >= 2) {
                        seenB = readScalarB()
                    }
                    if (scalarArity >= 3) {
                        seenC = readScalarC()
                    }
                    selfRevision = nextRevision(selfRevision)
                    fresh
            }
        } else {
            let current = sourceRevisions()
            match (cachedValue) {
                case Some(cached) where !revisionsDiffer(seenRevisions, current) => cached
                case _ =>
                    let fresh = compute()
                    cachedValue = Some(fresh)
                    seenRevisions = current
                    selfRevision = nextRevision(selfRevision)
                    fresh
            }
        }
    }

    // Reads source revisions left-to-right (the same order the array path collects them);
    // short-circuiting only skips reads whose outcome can no longer change the verdict.
    private func scalarRevisionsDiffer(): Bool {
        if (readScalarA() != seenA) {
            return true
        }
        if (scalarArity >= 2 && readScalarB() != seenB) {
            return true
        }
        scalarArity >= 3 && readScalarC() != seenC
    }
}

private func revisionsDiffer(previous: Array<UInt64>, current: Array<UInt64>): Bool {
    if (previous.size != current.size) {
        return true
    }
    var i: Int64 = 0
    while (i < previous.size) {
        if (previous[i] != current[i]) {
            return true
        }
        i += 1
    }
    false
}

/** Returns a read-only state computed from one source. */
public func derive<A, T>(source: Observable<A>, compute: (A) -> T): DerivedState<T> {
    DerivedState<T>(
        {=> compute(source.get())},
        {=> [source.revision]},
        {onChange =>
            let observation = source.observe({_, _ => onChange()})
            [{=> observation.close()}]
        },
        scalarArity: 1,
        readScalarA: {=> source.revision}
    )
}

/** Returns a read-only state computed from two sources. */
public func derive<A, B, T>(first: Observable<A>, second: Observable<B>, compute: (A, B) -> T): DerivedState<T> {
    DerivedState<T>(
        {=> compute(first.get(), second.get())},
        {=> [first.revision, second.revision]},
        {onChange =>
            let one = first.observe({_, _ => onChange()})
            let two = second.observe({_, _ => onChange()})
            [{=> one.close()}, {=> two.close()}]
        },
        scalarArity: 2,
        readScalarA: {=> first.revision},
        readScalarB: {=> second.revision}
    )
}

/** Returns a read-only state computed from three sources. */
public func derive<A, B, C, T>(
    first: Observable<A>,
    second: Observable<B>,
    third: Observable<C>,
    compute: (A, B, C) -> T
): DerivedState<T> {
    DerivedState<T>(
        {=> compute(first.get(), second.get(), third.get())},
        {=> [first.revision, second.revision, third.revision]},
        {onChange =>
            let one = first.observe({_, _ => onChange()})
            let two = second.observe({_, _ => onChange()})
            let three = third.observe({_, _ => onChange()})
            [{=> one.close()}, {=> two.close()}, {=> three.close()}]
        },
        scalarArity: 3,
        readScalarA: {=> first.revision},
        readScalarB: {=> second.revision},
        readScalarC: {=> third.revision}
    )
}

/**
 * Returns a read-only state computed from any number of same-typed sources. `compute` receives their
 * current values in source order. Use this when the source count is dynamic or exceeds the fixed
 * arity overloads — for example aggregating a list of per-item counters or toggles into one total.
 */
public func derive<A, T>(sources: Array<Observable<A>>, compute: (Array<A>) -> T): DerivedState<T> {
    DerivedState<T>(
        {=> compute(currentValues(sources))},
        {=> currentRevisions(sources)},
        {onChange =>
            let cancels = ArrayList<() -> Unit>()
            for (source in sources) {
                let observation = source.observe({_, _ => onChange()})
                cancels.add({=> observation.close()})
            }
            cancels.toArray()
        }
    )
}

private func currentValues<A>(sources: Array<Observable<A>>): Array<A> {
    Array<A>(sources.size, {i => sources[i].get()})
}

private func currentRevisions<A>(sources: Array<Observable<A>>): Array<UInt64> {
    Array<UInt64>(sources.size, {i => sources[i].revision})
}

/**
 * A writable projection of a component inside another bindable value, created with
 * `Bindable.project`. Reading delegates to the source; writing rebuilds the source
 * value around the changed component, so there is exactly one source of truth.
 */
public class Binding<T> <: Bindable<T> {
    private let read: () -> T
    private let write: (T) -> Unit
    private let revisionSource: () -> UInt64
    private let observeSource: ((T, T) -> Unit) -> StateObservation<T>

    init(
        read: () -> T,
        write: (T) -> Unit,
        revisionSource: () -> UInt64,
        observeSource: ((T, T) -> Unit) -> StateObservation<T>
    ) {
        this.read = read
        this.write = write
        this.revisionSource = revisionSource
        this.observeSource = observeSource
    }

    public mut prop value: T {
        get() {
            read()
        }
        set(next) {
            write(next)
        }
    }

    public prop revision: UInt64 {
        get() {
            revisionSource()
        }
    }

    public func observe(callback: (T, T) -> Unit): StateObservation<T> {
        observeSource(callback)
    }
}

/** Builds the binding behind `Bindable.project`. */
internal func bindingOf<S, T>(source: Bindable<S>, get: (S) -> T, set: (S, T) -> S): Binding<T> {
    Binding<T>(
        {=> get(source.value)},
        {next => source.value = set(source.value, next)},
        {=> source.revision},
        {callback =>
            let observation = source.observe({prev, cur => callback(get(prev), get(cur))})
            StateObservation<T>({=> observation.close()})
        }
    )
}
