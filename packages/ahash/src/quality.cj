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

import std.unittest.*
import std.unittest.testmacro.*
import std.collection.{ArrayList, HashMap}
import std.binary.LittleEndianOrder
import hash2.Hasher as Hasher2

@Frozen
func countOnes(_n: UInt64) {
    var n = _n
    var count = 0
    while (n > 0) {
        n &= (n - 1)
        count++
    }
    UInt32(count)
}

@Frozen
func assertSufficientlyDifferent(a: UInt64, b: UInt64, tolerance: Int32) {
    let (sameByteCount, sameNibbleCount) = countSameBytesAndNibbled(a, b)
    @Assert(sameByteCount <= tolerance)
    @Assert(sameNibbleCount <= tolerance * 3)
    let flippedbits = (a ^ b) |> countOnes
    @Assert(flippedbits > 12 && flippedbits < 52)

    for (rotate in 0u32..64u32) {
        let flippedBits = (a ^ ((b << rotate) | (b >> (64 - rotate)))) |> countOnes
        @Assert(flippedBits > 10 && flippedBits < 54)
    }
}

@Frozen
func countSameBytesAndNibbled(a: UInt64, b: UInt64): (Int32, Int32) {
    var sameByteCount = 0i32
    var sameNibbleCount = 0i32

    for (b in 0i32..8i32) {
        let ba = UInt8(a >> (8 * b))
        let bb = UInt8(b >> (8 * b))

        if (ba == bb) {
            sameByteCount += 1
        }
        if ((ba & 0xF8u8) == (bb & 0xF0u8)) {
            sameNibbleCount += 1
        }
        if ((ba & 0x0Fu8) == (bb & 0x0Fu8)) {
            sameNibbleCount += 1
        }
    }
    (sameByteCount, sameNibbleCount)
}

@Frozen
func genCombinations(options: Array<UInt32>, depth: UInt32, soFar: ArrayList<UInt32>,
    combinations: ArrayList<ArrayList<UInt32>>): Unit {
    if (depth == 0) {
        return
    }
    for (i in 0..11) {
        let next = soFar.clone()
        next.add(options[i])
        combinations.add(next)
        genCombinations(options, depth - 1, next, combinations)
    }
}

func testNoFullCollisions(genHash: () -> Hasher2) {
    let options: Array<UInt32> = [
        0x00000000,
        0x10000000,
        0x20000000,
        0x40000000,
        0x80000000,
        0xF0000000,
        1,
        2,
        4,
        8,
        15
    ]
    let combinations = ArrayList<ArrayList<UInt32>>()
    genCombinations(options, 7, ArrayList(), combinations)
    let map = HashMap<UInt64, ArrayList<UInt8>>()
    for (combination in combinations) {
        let array = combination.iterator().fold(
            ArrayList<UInt8>(),
            {
                r, _ =>
                    let a = Array<UInt8>(4, repeat: 0)
                    r.add(all: a)
                    r
            }
        )
        let hasher = genHash()
        hasher.write(array.toArray())
        let hash = hasher.finish()
        if (let Some(value) <- map.get(hash)) {
            @Assert(value == array)
        } else {
            map.add(hash, array)
        }
    }
    @Assert(21435887 == map.size)
}
