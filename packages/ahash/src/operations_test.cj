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
import i128.UInt128
import i128.helper.u128

@Test
class OperationsTest {
    @TestCase
    func shuffleContainsEachValue() {
        let value = @u128(0x00010203_04050607_08090A0B_0C0D0E0F)
        let shuffled = shuffle(value)

        let buf = Array<UInt8>(16, repeat: 0)
        shuffled.writeLittleEndian(buf)
        for (index in 0u8..16u8) {
            @Assert(buf.contains(index))
        }
    }

    @TestCase
    func shuffleMovesEveryValue() {
        let buf = Array<UInt8>(16, repeat: 0)
        for (index in 0..16) {
            buf[index] = 1
            let v = UInt128.readLittleEndian(buf)
            let shuffled = shuffle(v)

            shuffled.writeLittleEndian(buf)
            @Assert(0 == buf[index])
            buf.fill(0)
        }
    }

    @TestCase
    func shuffleMovesHighBits() {
        @Expect(shuffle(@u128(1)) > (@u128(1) << 80))
        @Expect(shuffle(@u128(1) << 58) >= (@u128(1) << 64))
        @Expect(shuffle(@u128(1) << 58) < (@u128(1) << 112))
        @Expect(shuffle(@u128(1) << 64) < (@u128(1) << 64))
        @Expect(shuffle(@u128(1) << 64) >= (@u128(1) << 16))
        @Expect(shuffle(@u128(1) << 120) < (@u128(1) << 50))
    }

    @TestCase
    func testAddlength() {
        var enc = UInt128(50, UInt64.Max)
        enc = addInLength(enc, UInt64.Max)
        @Assert(enc.lower(), UInt64.Max)
        @Assert(enc.upper(), 49)
    }
}
