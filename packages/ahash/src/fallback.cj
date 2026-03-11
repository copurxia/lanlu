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
import hash2.Hasher as Hasher2

const ROT = 23u32

public class FallbackAHasher {
    protected FallbackAHasher(var buffer: UInt64, var pad: UInt64, var extra_keys: VArray<UInt64, $2>) {
    }

    @Frozen
    protected static func newWithKey(_key1: UInt128, _key2: UInt128) {
        let key1 = (_key1 ^ PI_U128X2[0])
        let key2 = (_key2 ^ PI_U128X2[1])

        FallbackAHasher(key1.upper(), key1.lower(), [key2.upper(), key2.lower()])
    }

    @Frozen
    protected static func fromRandomState(randState: RandomState) {
        FallbackAHasher(randState.k1, randState.k0, [randState.k2, randState.k3])
    }

    @Frozen
    protected static func testWithKeys(key1: UInt128, key2: UInt128) {
        FallbackAHasher(key1.upper(), key2.lower(), [key2.upper(), key2.lower()])
    }

    @Frozen
    func update(new: UInt64) {
        this.buffer = foldMultiply(new ^ this.buffer, MULTIPLE)
    }

    @Frozen
    func largeUpdate(new: UInt128) {
        let combined = foldMultiply(new.upper() ^ this.extra_keys[0], new.lower() ^ this.extra_keys[1])
        this.buffer = ((this.buffer + this.pad) ^ ((combined << ROT) | (combined >> (64 - ROT))))
    }

    @Frozen
    public func clone() {
        FallbackAHasher(this.buffer, this.pad, this.extra_keys)
    }
}

extend FallbackAHasher <: Hasher2 {
    @Frozen
    public func write(input: Array<UInt8>) {
        var data = input
        let len = UInt64(data.size)
        this.buffer = (this.buffer + len) * MULTIPLE

        if (len > 8) {
            if (len > 16) {
                let tail = data[data.size - 16..]
                this.largeUpdate(UInt128.readLittleEndian(tail))

                while (data.size > 16) {
                    let (block, rest) = data.splitAt(16)
                    this.largeUpdate(UInt128.readLittleEndian(block))
                    data = rest
                }
            } else {
                let first = data[0..8]
                let end = data[data.size - 8..]

                this.largeUpdate(UInt128(UInt64.readLittleEndian(first), UInt64.readLittleEndian(end)))
            }
        } else {
            let value = readSmall(data)
            this.largeUpdate(UInt128(value[0], value[1]))
        }
    }

    @Frozen
    public func write(input: UInt8) {
        UInt64(input) |> this.write
    }

    @Frozen
    public func write(input: UInt16) {
        UInt64(input) |> this.write
    }

    @Frozen
    public func write(input: UInt32) {
        UInt64(input) |> this.write
    }

    @Frozen
    public func write(input: UInt64) {
        this.update(input)
    }

    @Frozen
    public func finish() {
        let rot = UInt32((this.buffer & 63))
        let by = if (rot != 0) {
            (pad << rot) | (pad >> (64 - rot))
        } else {
            pad
        }
        foldMultiply(this.buffer, by)
    }
}
