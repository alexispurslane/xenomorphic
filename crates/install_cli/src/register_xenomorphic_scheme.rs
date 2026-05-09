use client::XENOMORPHIC_URL_SCHEME;
use gpui::{AsyncApp, actions};

actions!(
    cli,
    [
        /// Registers the zed:// URL scheme handler.
        RegisterXenomorphicScheme
    ]
);

pub async fn register_xenomorphic_scheme(cx: &AsyncApp) -> anyhow::Result<()> {
    cx.update(|cx| cx.register_url_scheme(XENOMORPHIC_URL_SCHEME)).await
}
