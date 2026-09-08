use tracing_subscriber::EnvFilter;

/// Initialize JSON structured logging. Level from `RUST_LOG`, defaults to `info`.
pub fn init(service_name: &'static str) {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(filter)
        .init();
    tracing::info!(service = service_name, "telemetry initialized");
}
