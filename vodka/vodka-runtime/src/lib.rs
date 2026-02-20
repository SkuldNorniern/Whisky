pub fn normalize_wine_tag(input: &str) -> Option<String> {
    let mut value = input.trim();
    if value.is_empty() {
        return None;
    }

    if let Some(stripped) = value.strip_prefix("wine-") {
        value = stripped;
    }
    if let Some(stripped) = value.strip_prefix('v') {
        value = stripped;
    }

    let mut normalized = String::new();
    for ch in value.chars() {
        if ch.is_ascii_digit() || ch == '.' {
            normalized.push(ch);
        } else {
            break;
        }
    }

    if normalized.is_empty() {
        None
    } else {
        Some(normalized)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_wine_prefix() {
        assert_eq!(normalize_wine_tag("wine-11.2"), Some("11.2".to_string()));
    }

    #[test]
    fn normalizes_v_prefix() {
        assert_eq!(normalize_wine_tag("v9.21"), Some("9.21".to_string()));
    }

    #[test]
    fn trims_suffix() {
        assert_eq!(
            normalize_wine_tag("wine-8.0.1-rc1"),
            Some("8.0.1".to_string())
        );
    }

    #[test]
    fn rejects_non_numeric() {
        assert_eq!(normalize_wine_tag("release"), None);
    }
}
