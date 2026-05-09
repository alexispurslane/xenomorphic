fn main() {
    let cargo_toml =
        std::fs::read_to_string("../xenomorphic/Cargo.toml").expect("Failed to read crates/xenomorphic/Cargo.toml");
    let version = cargo_toml
        .lines()
        .find(|line| line.starts_with("version = "))
        .expect("Version not found in crates/xenomorphic/Cargo.toml")
        .split('=')
        .nth(1)
        .expect("Invalid version format")
        .trim()
        .trim_matches('"');
    println!("cargo:rerun-if-changed=../xenomorphic/Cargo.toml");
    println!("cargo:rustc-env=XENOMORPHIC_PKG_VERSION={}", version);
}
