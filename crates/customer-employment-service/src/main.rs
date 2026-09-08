mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("customer-employment-service");
    let settings = Settings::load(3007)?;
    let pool = db::create_pool(&settings.database.url).await?;
    let app = handler::router(pool);
    let addr = format!("{}:{}", settings.server.host, settings.server.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    tracing::info!(%addr, "listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};

    let mut sigterm = signal(SignalKind::terminate()).expect("failed to install SIGTERM handler");
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {},
        _ = sigterm.recv() => {},
    }
    tracing::info!("shutdown signal received, draining connections");
}
