// Copyright (c) 2025 Yan Mingshu <yms_hi@outlook.com>
// ahash is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//          http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
package ahash_smhasher

import ahash.{RandomState,AHasher}
import std.env.{getCommandLine,exit}

@C
public func ahash_cj(_buf: CPointer<UInt8>,len: UIntNative,seed: UInt32,out: CPointer<UInt64>){
    let buf = Array<UInt8>(Int64(len),repeat: 0)
    
    unsafe{for(i in 0..Int64(len)) {
        buf[i] = _buf.read(i)
    }}
    let hasher = RandomState.withSeeds(UInt64(seed),UInt64(seed),UInt64(seed),UInt64(seed)).buildHasher()
    hasher.write(buf)
    let r = hasher.finish()
    unsafe{out.write(r)}
}

foreign func smhasher_main(argc:Int64,argv:CPointer<CPointer<UInt8>>):Unit

main() {
    let command = getCommandLine()
    unsafe {
        let argc = command.size
        let argv = LibC.malloc<CPointer<UInt8>>(count: argc + 1)
        
        for (c in 0..command.size) {
            let str = LibC.mallocCString(command[c])
            argv.write(c,str.getChars())
        }
        argv.write(argc,CPointer())

        smhasher_main(argc,argv)
    }
}