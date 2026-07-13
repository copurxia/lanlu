use serde_json::Value;

/// Output mode
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum OutputMode {
    Text,
    Json,
    PrettyJson,
}

impl OutputMode {
    pub fn from_str(s: &str) -> Self {
        match s {
            "json" => OutputMode::Json,
            "pretty-json" => OutputMode::PrettyJson,
            _ => OutputMode::Text,
        }
    }
}

/// Print raw JSON response
pub fn print_raw(body: &str, mode: OutputMode) {
    match mode {
        OutputMode::Json => println!("{}", body),
        OutputMode::PrettyJson => {
            match serde_json::from_str::<Value>(body) {
                Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()),
                Err(_) => println!("{}", body),
            }
        }
        OutputMode::Text => println!("{}", body),
    }
}

/// Print JSON or text using a printer function
pub fn print_json_or_text(body: &str, mode: OutputMode, text_printer: fn(&str)) {
    match mode {
        OutputMode::Text => text_printer(body),
        OutputMode::PrettyJson => {
            match serde_json::from_str::<Value>(body) {
                Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()),
                Err(_) => println!("{}", body),
            }
        }
        OutputMode::Json => println!("{}", body),
    }
}
