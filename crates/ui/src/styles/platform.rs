/// The platform style to use when rendering UI.
///
/// This can be used to abstract over platform differences.
#[derive(Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Clone, Copy)]
pub enum PlatformStyle {
    /// Display in macOS style.
    Mac,
    /// Display in Linux style.
    Linux,
}

impl PlatformStyle {
    /// Returns the [`PlatformStyle`] for the current platform.
    pub const fn platform() -> Self {
        if cfg!(any(target_os = "linux", target_os = "freebsd")) {
            Self::Linux
        } else {
            Self::Mac
        }
    }
}
