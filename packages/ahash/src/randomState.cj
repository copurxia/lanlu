// Copyright (c) 2025 Yan Mingshu <yms_hi@outlook.com>
// ahash is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//          http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
package ahash

import constrandom.rMacro.constRandom
import i128.{UInt128, helper.u128}
import std.sync.AtomicUInt64
import hash2.HasherBuilder

func getFixedSeeds(): VArray<VArray<UInt64, $4>, $2> {
    [
        [
            @constRandom(UInt64),
            @constRandom(UInt64),
            @constRandom(UInt64),
            @constRandom(UInt64)
        ],
        [
            @constRandom(UInt64),
            @constRandom(UInt64),
            @constRandom(UInt64),
            @constRandom(UInt64)
        ]
    ]
}

protected const PI_U128X2: VArray<UInt128, $2> = [
    @u128(0x1319_8a2e_0370_7344_243f_6a88_85a3_08d3),
    @u128(0x082e_fa98_ec4e_6c89_a409_3822_299f_31d0)
]
protected const PI2: VArray<UInt64, $4> = [
    0x4528_21e6_38d0_1377,
    0xbe54_66cf_34e9_0c6c,
    0xc0ac_29b7_c97c_50dd,
    0x3f84_d5b5_b547_0917
]

public struct RandomState {
    @Frozen
    protected const RandomState(protected let k0: UInt64, protected let k1: UInt64, protected let k2: UInt64,
        protected let k3: UInt64) {}
}

extend RandomState <: ToString {
    @Frozen
    public func toString() {
        "RandomState( <PRIVATE> )"
    }
}

class DefaultRandomSource {
    let counter: AtomicUInt64
    let p: CPointer<UInt8>

    DefaultRandomSource() {
        p = LibC.malloc()
        counter = AtomicUInt64(@constRandom(UInt64))
    }

    ~init() {
        unsafe {
            LibC.free(this.p)
        }
    }

    @Frozen
    func genHasherSeed(): UInt64 {
        let stack = UInt64(this.p.toUIntNative())
        this.counter.fetchAdd(stack)
    }
}

let RANDOM_SOURCE = DefaultRandomSource()

extend RandomState {
    @Frozen
    public static func generateWith(k0: UInt64, k1: UInt64, k2: UInt64, k3: UInt64) {
        let fixed = getFixedSeeds()
        RandomState.fromKeys(fixed[0], [k0, k1, k2, k3], RANDOM_SOURCE.genHasherSeed())
    }

    public static func new() {
        let fixed = getFixedSeeds()
        RandomState.fromKeys(fixed[0], fixed[1], RANDOM_SOURCE.genHasherSeed())
    }

    @Frozen
    static func fromKeys(a: VArray<UInt64, $4>, b: VArray<UInt64, $4>, c: UInt): RandomState {
        let hasher = FallbackAHasher.fromRandomState(RandomState(a[0], a[1], a[2], a[3]))
        hasher.write(c)

        let mix = {
            l: UInt64, r: UInt64 =>
                let h = hasher.clone()
                h.write(l)
                h.write(r)
                h.finish()
        }
        RandomState(mix(b[0], b[2]), mix(b[1], b[3]), mix(b[2], b[1]), mix(b[3], b[0]))
    }

    @Frozen
    public static func withSeed(key: UInt64): RandomState {
        let fixed = getFixedSeeds()
        RandomState.fromKeys(fixed[0], fixed[1], key)
    }

    public static func withSeeds(k0: UInt64, k1: UInt64, k2: UInt64, k3: UInt64): RandomState {
        RandomState(k0 ^ PI2[0], k1 ^ PI2[1], k2 ^ PI2[2], k3 ^ PI2[3])
    }
}

extend RandomState <: HasherBuilder<AHasher> {
    public func buildHasher(): AHasher {
        AHasher.fromRandomState(this)
    }
}
