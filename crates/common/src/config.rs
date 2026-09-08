use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Settings {
    pub database: DatabaseSettings,
    pub server: ServerSettings,
}

#[derive(Deserialize)]
pub struct DatabaseSettings {
    pub url: String,
}

impl std::fmt::Debug for DatabaseSettings {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("DatabaseSettings")
            .field("url", &"<redacted>")
            .finish()
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn database_url_is_redacted_in_debug() {
        let db = DatabaseSettings {
            url: "postgres://user:secret@host:5432/db".to_owned(),
        };
        let rendered = format!("{db:?}");
        assert!(rendered.contains("<redacted>"));
        assert!(!rendered.contains("secret"));
    }
}
