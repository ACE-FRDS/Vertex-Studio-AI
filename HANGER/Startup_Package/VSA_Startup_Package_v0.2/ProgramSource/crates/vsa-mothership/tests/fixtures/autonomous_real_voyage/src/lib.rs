pub fn vertex_voyage_probe() -> &'static str {
    "VERTEX_REAL_BUILD_OK"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn real_test_process_passes() {
        assert_eq!(vertex_voyage_probe(), "VERTEX_REAL_BUILD_OK");
    }
}
