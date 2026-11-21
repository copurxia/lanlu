/// Simple percent-encoding for URL path/query segments.
pub fn url_encode(s: &str) -> String {
    let mut result = String::new();
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                result.push(byte as char);
            }
            b' ' => result.push_str("%20"),
            _ => {
                result.push_str(&format!("%{:02X}", byte));
            }
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn url_encode_leaves_unreserved_untouched() {
        assert_eq!(url_encode("AZaz09-_.~"), "AZaz09-_.~");
    }

    #[test]
    fn url_encode_handles_empty_input() {
        assert_eq!(url_encode(""), "");
    }

    #[test]
    fn url_encode_encodes_space_as_percent20() {
        assert_eq!(url_encode("a b"), "a%20b");
    }

    #[test]
    fn url_encode_encodes_multibyte_utf8_by_byte() {
        // '中' is E4 B8 AD in UTF-8
        assert_eq!(url_encode("中"), "%E4%B8%AD");
    }

    #[test]
    fn url_encode_encodes_reserved_characters() {
        assert_eq!(url_encode("/?&="), "%2F%3F%26%3D");
    }
}
