fn main() {
    if let Ok(bundled) = std::env::var("XENOMORPHIC_BUNDLE") {
        println!("cargo:rustc-env=XENOMORPHIC_BUNDLE={}", bundled);
    }
}
