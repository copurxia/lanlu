package totp_cj

@Test
public class TotpTestSuite {
    @TestCase
    public func testBase32RoundTrip(): Unit {
        let secret = "hello world".toArray()
        let encoded = base32Encode(secret)
        let decoded = base32Decode(encoded)
        @Assert(String.fromUtf8(decoded), "hello world")
    }

    @TestCase
    public func testBase32IgnoresPaddingAndWhitespace(): Unit {
        let decoded = base32Decode("JBSW Y3DP-EHPK3PXP==")
        @Assert(decoded.size > 0, true)
        @Assert(base32Encode(decoded), "JBSWY3DPEHPK3PXP")
    }

    @TestCase
    public func testRfc6238Sha1Vectors(): Unit {
        let secret = base32Encode("12345678901234567890".toArray())
        @Assert(generateCodeCustom(secret, 59, 30, 8, "SHA1"), "94287082")
        @Assert(generateCodeCustom(secret, 1111111109, 30, 8, "SHA1"), "07081804")
        @Assert(generateCodeCustom(secret, 1111111111, 30, 8, "SHA1"), "14050471")
        @Assert(generateCodeCustom(secret, 1234567890, 30, 8, "SHA1"), "89005924")
        @Assert(generateCodeCustom(secret, 2000000000, 30, 8, "SHA1"), "69279037")
        @Assert(generateCodeCustom(secret, 20000000000, 30, 8, "SHA1"), "65353130")
    }

    @TestCase
    public func testVerifyWindow(): Unit {
        let secret = base32Encode("12345678901234567890".toArray())
        let code = generateCode(secret, 90)
        @Assert(verifyCode(secret, code, 119, window: 1), true)
        @Assert(verifyCode(secret, code, 151, window: 0), false)
    }
}
