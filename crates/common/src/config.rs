use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub database: DatabaseSettings,
    pub server: ServerSettings,
}

#[derive(Debug, Deserialize)]
pub struct DatabaseSettings {
    pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct ServerSettings {
    pub host: String,
    pub port: u16,
}

impl Settings {
    /// Load configuration from `APP__*` environment variables.
    /// `default_port` is the service-specific default port.
    ///
    /// # Errors
    /// Returns `config::ConfigError` when `APP__DATABASE__URL` is missing
    /// or a value cannot be parsed.
    pub fn load(default_port: u16) -> Result<Self, config::ConfigError> {
        config::Config::builder()
            .set_default("server.host", "0.0.0.0")?
            .set_default("server.port", i64::from(default_port))?
            .add_source(
                config::Environment::with_prefix("APP")
                    .separator("__")
                    .try_parsing(true),
            )
            .build()?
            .try_deserialize()
    }
}
