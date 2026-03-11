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
import i128.{UInt128, helper.u128}

@Test
func hashTest() {
    var hasher = FallbackAHasher.newWithKey(@u128(0), @u128(0))
    let value = 1u64 << 32
    hasher.update(value)
    let result = hasher.buffer
    hasher = FallbackAHasher.newWithKey(@u128(0), @u128(0))
    let value2 = 1u64
    hasher.update(value2)
    let result2 = hasher.buffer
    @Expect(result != result2)
}
