package argon2_ffi

foreign {
    func argon2id_hash_encoded(
        t_cost: UInt32,
        m_cost: UInt32,
        parallelism: UInt32,
        pwd: CString,
        pwdlen: UIntNative,
        salt: CString,
        saltlen: UIntNative,
        hashlen: UIntNative,
        encoded: CString,
        encodedlen: UIntNative
    ): Int32

    func argon2id_verify(encoded: CString, pwd: CString, pwdlen: UIntNative): Int32
    func argon2_error_message(errorCode: Int32): CString
}

public const ARGON2_OK: Int32 = 0

public class Argon2 {
    public static func hashEncoded(
        tCost: UInt32,
        mCost: UInt32,
        parallelism: UInt32,
        pwd: CString,
        pwdlen: UIntNative,
        salt: CString,
        saltlen: UIntNative,
        hashlen: UIntNative,
        encoded: CString,
        encodedlen: UIntNative
    ): Int32 {
        return unsafe {
            argon2id_hash_encoded(
                tCost,
                mCost,
                parallelism,
                pwd,
                pwdlen,
                salt,
                saltlen,
                hashlen,
                encoded,
                encodedlen
            )
        }
    }

    public static func verifyEncoded(encoded: CString, pwd: CString, pwdlen: UIntNative): Int32 {
        return unsafe { argon2id_verify(encoded, pwd, pwdlen) }
    }

    public static func errorMessage(errorCode: Int32): String {
        let raw = unsafe { argon2_error_message(errorCode) }
        if (raw.isNull()) {
            return "unknown error"
        }
        return unsafe { raw.toString() }
    }
}
