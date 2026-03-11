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

import std.binary.LittleEndianOrder
import i128.UInt128

protected const MULTIPLE: UInt64 = 6364136223846793005

@Frozen
protected const func foldMultiply(s: UInt64, by: UInt64): UInt64 {
    let result = UInt128(s) * UInt128(by)
    result.lower() ^ result.upper()
}

/**
 * 输入必须小于八字节
 */
@Frozen
protected func readSmall(data: Array<UInt8>): VArray<UInt64, $2> {
    if (data.size >= 2) {
        if (data.size >= 4) {
            let first = data[0..4] |> UInt32.readLittleEndian
            let end = data[data.size - 4..data.size] |> UInt32.readLittleEndian

            [UInt64(first), UInt64(end)]
        } else {
            let first = data[0..2] |> UInt16.readLittleEndian
            let end = data[data.size - 2..data.size] |> UInt16.readLittleEndian

            [UInt64(first), UInt64(end)]
        }
    } else {
        if (data.size > 0) {
            [UInt64(data[0]), UInt64(data[0])]
        } else {
            [0, 0]
        }
    }
}

@Frozen
protected func shuffle(a: UInt128): UInt128 {
    a.swapBytes()
}

@Frozen
protected func addAndShuffle(a: UInt128, b: UInt128) {
    let sum = a + b
    shuffle(sum)
}

@Frozen
protected func shuffleAndAdd(base: UInt128, toAdd: UInt128) {
    let shuffled = shuffle(base)
    shuffled + toAdd
}

@Frozen
protected const func addBy64s(a: UInt128, b: UInt128): UInt128 {
    UInt128(a.upper() + b.upper(), a.lower() + b.lower())
}

@Frozen
protected func addInLength(enc: UInt128, len: UInt64) {
    UInt128(enc.upper() + len, enc.lower())
}
