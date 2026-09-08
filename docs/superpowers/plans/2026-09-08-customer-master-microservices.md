# Banking Customer Master Microservices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build 8 read-only REST/JSON microservices (one per table in `DDL.sql`), each exposing a paginated `readAll` GET endpoint returning 100 records per page.

**Architecture:** Cargo workspace with a shared `common` library crate (config, db pool, pagination, errors, telemetry) and 8 thin binary crates, one per table, each on its own port (3001–3008). Each service: axum router → handler → repository (sqlx, parameterized static SQL) → Postgres.

**Tech Stack:** Rust 2024, tokio, axum 0.8, sqlx 0.8 (Postgres, rustls), serde, tracing/tracing-subscriber (JSON), config 0.15, thiserror 2, tower-http (trace), chrono, bigdecimal, anyhow.

**Spec:** `docs/superpowers/specs/2026-09-08-customer-master-microservices-design.md`

## Global Constraints

- Rust edition **2024**; `cargo clippy --all-targets --all-features -- -D warnings` must pass clean; `cargo fmt --all` enforced.
- Secrets: **never** hardcoded. Database URL comes from `APP__DATABASE__URL` env var only.
- SQL: static query literals with `$1`/`$2` bind parameters only. No string-built SQL.
- Pagination contract: `page` default 1 (reject `page < 1` with 400); `page_size` default 100, max 100 (reject outside `1..=100` with 400). Error body: `{ "error": "<message>" }`.
- Malformed query *types* (e.g. `?page=abc`) are rejected by axum's `Query` extractor before the handler: 400 with axum's plain-text body. This is a deliberate, documented contract detail; semantic violations (`page=0`, `page_size=101`) go through our JSON error contract.
- Out-of-range page (e.g. page 11 of 10) → `200` with empty `data` array.
- Response envelope: `{ "data": [...], "pagination": { "page", "page_size", "total_records", "total_pages" } }`.
- PG enums map to Rust enums via `sqlx::Type` + serde, JSON values identical to DB strings.
- Service → port/route/table/PK/expected-rows map (DML-seeded `bankdb`):

| Service | Port | Route | Table | PK | Rows |
|---|---|---|---|---|---|
| party-service | 3001 | /parties | parties | party_id | 1000 |
| individual-profile-service | 3002 | /individual-profiles | individual_profiles | individual_id | 800 |
| corporate-profile-service | 3003 | /corporate-profiles | corporate_profiles | corporate_id | 200 |
| customer-address-service | 3004 | /customer-addresses | customer_addresses | address_id | 1000 |
| customer-contact-service | 3005 | /customer-contacts | customer_contacts | contact_id | 1000 |
| customer-identification-service | 3006 | /customer-identifications | customer_identifications | identification_id | 1000 |
| customer-employment-service | 3007 | /customer-employment | customer_employment | employment_id | 800 |
| customer-kyc-service | 3008 | /customer-kyc | customer_kyc | kyc_id | 1000 |

- Verification DB: `postgresql://harir@localhost:5432/bankdb` (local dev, already seeded).
- Commit steps below assume git is initialized (Task 1, Step 1). If the user declined git, skip all commit steps.

---

### Task 1: Workspace scaffold + `common` crate

**Files:**
- Create: `Cargo.toml`
- Create: `crates/common/Cargo.toml`
- Create: `crates/common/src/lib.rs`
- Create: `crates/common/src/pagination.rs`
- Create: `crates/common/src/error.rs`
- Create: `crates/common/src/config.rs`
- Create: `crates/common/src/db.rs`
- Create: `crates/common/src/telemetry.rs`

**Interfaces:**
- Consumes: nothing (first task).
- Produces (all later tasks rely on these exact signatures):
  - `common::pagination::PageParams { page: Option<u64>, page_size: Option<u64> }` — `#[derive(Debug, Default, Deserialize)]`
  - `PageParams::validate(self) -> Result<ValidatedPage, AppError>`
  - `common::pagination::ValidatedPage { page: u64, page_size: u64 }` with `.limit() -> i64`, `.offset() -> i64`
  - `common::pagination::Page<T> { data: Vec<T>, pagination: PageMeta }` — `Page::new(data: Vec<T>, page: ValidatedPage, total_records: u64) -> Page<T>`
  - `common::error::AppError` (`InvalidPagination(String)`, `Database(#[from] sqlx::Error)`), implements `IntoResponse`
  - `common::config::Settings::load(default_port: u16) -> Result<Settings, config::ConfigError>`; fields `settings.database.url: String`, `settings.server.host: String`, `settings.server.port: u16`
  - `common::db::create_pool(database_url: &str) -> Result<PgPool, sqlx::Error>`
  - `common::telemetry::init(service_name: &'static str)`

- [ ] **Step 1: Initialize workspace root**

If git was approved: `git init` in `/Users/harir/workspace/rustapp` and create `.gitignore` containing `/target`.

Create `Cargo.toml`:

```toml
[workspace]
resolver = "3"
members = ["crates/*"]

[workspace.package]
edition = "2024"

[workspace.dependencies]
common = { path = "crates/common" }
anyhow = "1"
axum = "0.8"
bigdecimal = { version = "0.4", features = ["serde"] }
chrono = { version = "0.4", features = ["serde"] }
config = "0.15"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
sqlx = { version = "0.8", default-features = false, features = [
    "runtime-tokio-rustls",
    "postgres",
    "chrono",
    "bigdecimal",
] }
thiserror = "2"
tokio = { version = "1", features = ["macros", "rt-multi-thread", "signal", "net"] }
tower-http = { version = "0.6", features = ["trace"] }
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["json", "env-filter"] }
```

Create `crates/common/Cargo.toml`:

```toml
[package]
name = "common"
version = "0.1.0"
edition.workspace = true

[dependencies]
axum.workspace = true
config.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
thiserror.workspace = true
tracing.workspace = true
tracing-subscriber.workspace = true
```

Create `crates/common/src/lib.rs`:

```rust
pub mod config;
pub mod db;
pub mod error;
pub mod pagination;
pub mod telemetry;
```

- [ ] **Step 2: Write the failing pagination tests**

Create `crates/common/src/pagination.rs` containing ONLY the test module (types do not exist yet):

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_are_applied() {
        let page = PageParams::default().validate().unwrap();
        assert_eq!(
            page,
            ValidatedPage {
                page: 1,
                page_size: 100
            }
        );
    }

    #[test]
    fn page_zero_is_rejected() {
        let err = PageParams {
            page: Some(0),
            page_size: None,
        }
        .validate()
        .unwrap_err();
        assert!(matches!(err, AppError::InvalidPagination(_)));
    }

    #[test]
    fn page_size_zero_is_rejected() {
        let result = PageParams {
            page: None,
            page_size: Some(0),
        }
        .validate();
        assert!(result.is_err());
    }

    #[test]
    fn page_size_above_max_is_rejected() {
        let result = PageParams {
            page: None,
            page_size: Some(101),
        }
        .validate();
        assert!(result.is_err());
    }

    #[test]
    fn page_size_at_max_is_accepted() {
        let page = PageParams {
            page: Some(3),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        assert_eq!(page.limit(), 100);
        assert_eq!(page.offset(), 200);
    }

    #[test]
    fn total_pages_rounds_up() {
        let page = PageParams {
            page: Some(1),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        let p: Page<()> = Page::new(vec![], page, 801);
        assert_eq!(p.pagination.total_pages, 9);
        let p: Page<()> = Page::new(vec![], page, 1000);
        assert_eq!(p.pagination.total_pages, 10);
        let p: Page<()> = Page::new(vec![], page, 0);
        assert_eq!(p.pagination.total_pages, 0);
    }

    #[test]
    fn huge_page_does_not_overflow() {
        let page = PageParams {
            page: Some(u64::MAX),
            page_size: Some(100),
        }
        .validate()
        .unwrap();
        assert_eq!(page.offset(), i64::MAX);
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `. "$HOME/.cargo/env" && cargo test -p common`
Expected: FAIL — compile errors, `PageParams`/`ValidatedPage`/`Page`/`AppError` not found. (This also resolves and downloads all dependencies on first run.)

- [ ] **Step 4: Implement pagination, error, config, db, telemetry**

Replace the whole of `crates/common/src/pagination.rs` with (implementation above the same tests):

```rust
use serde::{Deserialize, Serialize};

use crate::error::AppError;

pub const DEFAULT_PAGE: u64 = 1;
pub const DEFAULT_PAGE_SIZE: u64 = 100;
pub const MAX_PAGE_SIZE: u64 = 100;

/// Raw query parameters for paginated endpoints.
#[derive(Debug, Default, Deserialize)]
pub struct PageParams {
    pub page: Option<u64>,
    pub page_size: Option<u64>,
}

impl PageParams {
    /// Apply defaults and enforce bounds.
    ///
    /// # Errors
    /// Returns `AppError::InvalidPagination` when `page` is 0 or
    /// `page_size` is outside `1..=MAX_PAGE_SIZE`.
    pub fn validate(self) -> Result<ValidatedPage, AppError> {
        let page = self.page.unwrap_or(DEFAULT_PAGE);
        let page_size = self.page_size.unwrap_or(DEFAULT_PAGE_SIZE);
        if page == 0 {
            return Err(AppError::InvalidPagination(
                "page must be greater than or equal to 1".to_owned(),
            ));
        }
        if page_size == 0 || page_size > MAX_PAGE_SIZE {
            return Err(AppError::InvalidPagination(format!(
                "page_size must be between 1 and {MAX_PAGE_SIZE}"
            )));
        }
        Ok(ValidatedPage { page, page_size })
    }
}

/// Pagination values that have passed validation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ValidatedPage {
    pub page: u64,
    pub page_size: u64,
}

impl ValidatedPage {
    #[must_use]
    pub fn limit(&self) -> i64 {
        i64::try_from(self.page_size).unwrap_or(i64::MAX)
    }

    #[must_use]
    pub fn offset(&self) -> i64 {
        let offset = (self.page - 1).saturating_mul(self.page_size);
        i64::try_from(offset).unwrap_or(i64::MAX)
    }
}

/// Pagination metadata block of the response envelope.
#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct PageMeta {
    pub page: u64,
    pub page_size: u64,
    pub total_records: u64,
    pub total_pages: u64,
}

/// Standard paginated response envelope.
#[derive(Debug, Serialize)]
pub struct Page<T> {
    pub data: Vec<T>,
    pub pagination: PageMeta,
}

impl<T> Page<T> {
    #[must_use]
    pub fn new(data: Vec<T>, page: ValidatedPage, total_records: u64) -> Self {
        Self {
            data,
            pagination: PageMeta {
                page: page.page,
                page_size: page.page_size,
                total_records,
                total_pages: total_records.div_ceil(page.page_size),
            },
        }
    }
}

// ... keep the test module from Step 2 unchanged below this line ...
```

Create `crates/common/src/error.rs`:

```rust
use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("invalid pagination parameters: {0}")]
    InvalidPagination(String),
    #[error("database error")]
    Database(#[from] sqlx::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = match &self {
            AppError::InvalidPagination(_) => StatusCode::BAD_REQUEST,
            AppError::Database(err) => {
                tracing::error!(error = %err, "database query failed");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        };
        (status, Json(json!({ "error": self.to_string() }))).into_response()
    }
}
```

Create `crates/common/src/config.rs`:

```rust
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
```

Create `crates/common/src/db.rs`:

```rust
use sqlx::{PgPool, postgres::PgPoolOptions};

/// Create a Postgres connection pool.
///
/// # Errors
/// Returns `sqlx::Error` if the database is unreachable or credentials are invalid.
pub async fn create_pool(database_url: &str) -> Result<PgPool, sqlx::Error> {
    PgPoolOptions::new()
        .max_connections(5)
        .connect(database_url)
        .await
}
```

Create `crates/common/src/telemetry.rs`:

```rust
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `. "$HOME/.cargo/env" && cargo test -p common`
Expected: PASS — 7 tests pass.

- [ ] **Step 6: Lint and format gate**

Run: `. "$HOME/.cargo/env" && cargo clippy -p common --all-targets -- -D warnings && cargo fmt --all`
Expected: clippy clean, no diff left unformatted.

- [ ] **Step 7: Commit**

```bash
git add Cargo.toml Cargo.lock crates/common .gitignore
git commit -m "feat: workspace scaffold and shared common crate"
```

---

### Task 2: party-service (reference service)

**Files:**
- Create: `crates/party-service/Cargo.toml`
- Create: `crates/party-service/src/main.rs`
- Create: `crates/party-service/src/domain.rs`
- Create: `crates/party-service/src/repository.rs`
- Create: `crates/party-service/src/handler.rs`

**Interfaces:**
- Consumes: everything from Task 1 (`Settings::load`, `create_pool`, `telemetry::init`, `PageParams`, `ValidatedPage`, `Page`, `AppError`).
- Produces: the file-layout pattern all later service tasks follow: `main.rs` (bootstrap), `domain.rs` (row struct + enums), `repository.rs` (`find_all(&PgPool, ValidatedPage) -> Result<(Vec<T>, u64), sqlx::Error>`), `handler.rs` (`router(pool: PgPool) -> Router` with `/health` + resource route, `TraceLayer`, state = pool).

- [ ] **Step 1: Create the crate files**

`crates/party-service/Cargo.toml`:

```toml
[package]
name = "party-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/party-service/src/domain.rs`:

```rust
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "party_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PartyType {
    In,
    Corp,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "customer_segment_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CustomerSegment {
    Retail,
    Wealth,
    Sme,
    Corporate,
    Institutional,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "customer_status_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CustomerStatus {
    Pending,
    Active,
    Inactive,
    Dormant,
    Suspended,
    Closed,
}

#[derive(Debug, FromRow, Serialize)]
pub struct Party {
    pub party_id: i64,
    pub party_type: PartyType,
    pub customer_segment: CustomerSegment,
    pub customer_status: CustomerStatus,
    pub onboarding_date: DateTime<Utc>,
    pub home_branch_id: String,
    pub preferred_language: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
```

`crates/party-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::Party;

/// Fetch one page of parties plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<Party>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, Party>(
        "SELECT party_id, party_type, customer_segment, customer_status, \
         onboarding_date, home_branch_id, preferred_language, created_at, updated_at \
         FROM parties ORDER BY party_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM parties")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/party-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::Party, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/parties", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<Party>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/party-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("party-service");
    let settings = Settings::load(3001)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build**

Run: `. "$HOME/.cargo/env" && cargo build -p party-service`
Expected: compiles with no warnings.

- [ ] **Step 3: Clippy**

Run: `. "$HOME/.cargo/env" && cargo clippy -p party-service --all-targets -- -D warnings`
Expected: clean.

- [ ] **Step 4: Live smoke test against bankdb**

Run:

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/party-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3001/parties?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].party_id}'
curl -s "http://localhost:3001/parties?page=2&page_size=100" | jq '.data[0].party_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3001/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3001/parties?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3001/parties?page_size=101"
curl -s "http://localhost:3001/parties?page=11" | jq '.data | length'
kill $SVC_PID
```

Expected, in order:
- `{"rows":100,"page":1,"total":1000,"pages":10,"first_id":1}`
- `101`
- `200`
- `400`
- `400`
- `0` (page beyond last → empty data, still 200)

Also confirm the JSON enum values look like `"party_type":"IN"`, `"customer_status":"ACTIVE"` in raw curl output.

- [ ] **Step 5: Commit**

```bash
git add crates/party-service
git commit -m "feat: party-service readAll endpoint"
```

---

### Task 3: individual-profile-service

**Files:**
- Create: `crates/individual-profile-service/Cargo.toml`
- Create: `crates/individual-profile-service/src/main.rs`
- Create: `crates/individual-profile-service/src/domain.rs`
- Create: `crates/individual-profile-service/src/repository.rs`
- Create: `crates/individual-profile-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1 (same as Task 2).
- Produces: `individual-profile-service` binary, port 3002, route `/individual-profiles`.

- [ ] **Step 1: Create the crate files**

`crates/individual-profile-service/Cargo.toml`:

```toml
[package]
name = "individual-profile-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/individual-profile-service/src/domain.rs`:

```rust
use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, FromRow, Serialize)]
pub struct IndividualProfile {
    pub individual_id: i64,
    pub party_id: i64,
    pub title: Option<String>,
    pub first_name: String,
    pub middle_name: Option<String>,
    pub last_name: String,
    pub preferred_name: Option<String>,
    pub date_of_birth: NaiveDate,
    pub gender: Option<String>,
    pub marital_status: Option<String>,
    pub nationality: String,
    pub citizenship_status: Option<String>,
    pub mother_maiden_name: Option<String>,
}
```

`crates/individual-profile-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::IndividualProfile;

/// Fetch one page of individual profiles plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<IndividualProfile>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, IndividualProfile>(
        "SELECT individual_id, party_id, title, first_name, middle_name, last_name, \
         preferred_name, date_of_birth, gender, marital_status, nationality, \
         citizenship_status, mother_maiden_name \
         FROM individual_profiles ORDER BY individual_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM individual_profiles")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/individual-profile-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::IndividualProfile, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/individual-profiles", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<IndividualProfile>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/individual-profile-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("individual-profile-service");
    let settings = Settings::load(3002)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p individual-profile-service && cargo clippy -p individual-profile-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/individual-profile-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3002/individual-profiles?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].individual_id}'
curl -s "http://localhost:3002/individual-profiles?page=2&page_size=100" | jq '.data[0].individual_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3002/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3002/individual-profiles?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3002/individual-profiles?page_size=101"
curl -s "http://localhost:3002/individual-profiles?page=9" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":800,"pages":8,"first_id":1}` · `101` · `200` · `400` · `400` · `0`.

- [ ] **Step 4: Commit**

```bash
git add crates/individual-profile-service
git commit -m "feat: individual-profile-service readAll endpoint"
```

---

### Task 4: corporate-profile-service

**Files:**
- Create: `crates/corporate-profile-service/Cargo.toml`
- Create: `crates/corporate-profile-service/src/main.rs`
- Create: `crates/corporate-profile-service/src/domain.rs`
- Create: `crates/corporate-profile-service/src/repository.rs`
- Create: `crates/corporate-profile-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1.
- Produces: `corporate-profile-service` binary, port 3003, route `/corporate-profiles`.

- [ ] **Step 1: Create the crate files**

`crates/corporate-profile-service/Cargo.toml`:

```toml
[package]
name = "corporate-profile-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/corporate-profile-service/src/domain.rs`:

```rust
use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, FromRow, Serialize)]
pub struct CorporateProfile {
    pub corporate_id: i64,
    pub party_id: i64,
    pub company_name: String,
    pub trade_name: Option<String>,
    pub registration_number: String,
    pub incorporation_date: NaiveDate,
    pub country_of_inc: String,
    pub industry_code: String,
    pub business_structure: String,
    pub tax_identification: String,
}
```

`crates/corporate-profile-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CorporateProfile;

/// Fetch one page of corporate profiles plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CorporateProfile>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CorporateProfile>(
        "SELECT corporate_id, party_id, company_name, trade_name, registration_number, \
         incorporation_date, country_of_inc, industry_code, business_structure, \
         tax_identification \
         FROM corporate_profiles ORDER BY corporate_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM corporate_profiles")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/corporate-profile-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CorporateProfile, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/corporate-profiles", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CorporateProfile>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/corporate-profile-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("corporate-profile-service");
    let settings = Settings::load(3003)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p corporate-profile-service && cargo clippy -p corporate-profile-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/corporate-profile-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3003/corporate-profiles?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].corporate_id}'
curl -s "http://localhost:3003/corporate-profiles?page=2&page_size=100" | jq '.data[0].corporate_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3003/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3003/corporate-profiles?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3003/corporate-profiles?page_size=101"
curl -s "http://localhost:3003/corporate-profiles?page=3" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":200,"pages":2,"first_id":1}` · `101` · `200` · `400` · `400` · `0`.

- [ ] **Step 4: Commit**

```bash
git add crates/corporate-profile-service
git commit -m "feat: corporate-profile-service readAll endpoint"
```

---

### Task 5: customer-address-service

**Files:**
- Create: `crates/customer-address-service/Cargo.toml`
- Create: `crates/customer-address-service/src/main.rs`
- Create: `crates/customer-address-service/src/domain.rs`
- Create: `crates/customer-address-service/src/repository.rs`
- Create: `crates/customer-address-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1.
- Produces: `customer-address-service` binary, port 3004, route `/customer-addresses`.

- [ ] **Step 1: Create the crate files**

`crates/customer-address-service/Cargo.toml`:

```toml
[package]
name = "customer-address-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/customer-address-service/src/domain.rs`:

```rust
use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "address_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AddressType {
    Residential,
    Mailing,
    Registered,
    Office,
    Billing,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerAddress {
    pub address_id: i64,
    pub party_id: i64,
    pub address_type: AddressType,
    pub address_line_1: String,
    pub address_line_2: Option<String>,
    pub city: String,
    pub state_province: Option<String>,
    pub postal_code: Option<String>,
    pub country_code: String,
    pub is_primary: bool,
    pub effective_from: NaiveDate,
    pub effective_to: Option<NaiveDate>,
}
```

`crates/customer-address-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CustomerAddress;

/// Fetch one page of customer addresses plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CustomerAddress>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CustomerAddress>(
        "SELECT address_id, party_id, address_type, address_line_1, address_line_2, \
         city, state_province, postal_code, country_code, is_primary, \
         effective_from, effective_to \
         FROM customer_addresses ORDER BY address_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM customer_addresses")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/customer-address-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CustomerAddress, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/customer-addresses", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CustomerAddress>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/customer-address-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("customer-address-service");
    let settings = Settings::load(3004)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p customer-address-service && cargo clippy -p customer-address-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/customer-address-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3004/customer-addresses?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].address_id}'
curl -s "http://localhost:3004/customer-addresses?page=2&page_size=100" | jq '.data[0].address_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3004/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3004/customer-addresses?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3004/customer-addresses?page_size=101"
curl -s "http://localhost:3004/customer-addresses?page=11" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":1000,"pages":10,"first_id":1}` · `101` · `200` · `400` · `400` · `0`.

- [ ] **Step 4: Commit**

```bash
git add crates/customer-address-service
git commit -m "feat: customer-address-service readAll endpoint"
```

---

### Task 6: customer-contact-service

**Files:**
- Create: `crates/customer-contact-service/Cargo.toml`
- Create: `crates/customer-contact-service/src/main.rs`
- Create: `crates/customer-contact-service/src/domain.rs`
- Create: `crates/customer-contact-service/src/repository.rs`
- Create: `crates/customer-contact-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1.
- Produces: `customer-contact-service` binary, port 3005, route `/customer-contacts`.

- [ ] **Step 1: Create the crate files**

`crates/customer-contact-service/Cargo.toml`:

```toml
[package]
name = "customer-contact-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/customer-contact-service/src/domain.rs`:

```rust
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "contact_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ContactType {
    Mobile,
    Landline,
    WorkPhone,
    Email,
    Fax,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerContact {
    pub contact_id: i64,
    pub party_id: i64,
    pub contact_type: ContactType,
    pub country_dial_code: Option<String>,
    pub contact_value: String,
    pub is_primary: bool,
    pub is_verified: bool,
    pub opt_in_marketing: bool,
}
```

`crates/customer-contact-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CustomerContact;

/// Fetch one page of customer contacts plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CustomerContact>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CustomerContact>(
        "SELECT contact_id, party_id, contact_type, country_dial_code, contact_value, \
         is_primary, is_verified, opt_in_marketing \
         FROM customer_contacts ORDER BY contact_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM customer_contacts")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/customer-contact-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CustomerContact, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/customer-contacts", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CustomerContact>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/customer-contact-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("customer-contact-service");
    let settings = Settings::load(3005)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p customer-contact-service && cargo clippy -p customer-contact-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/customer-contact-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3005/customer-contacts?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].contact_id}'
curl -s "http://localhost:3005/customer-contacts?page=2&page_size=100" | jq '.data[0].contact_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3005/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3005/customer-contacts?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3005/customer-contacts?page_size=101"
curl -s "http://localhost:3005/customer-contacts?page=11" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":1000,"pages":10,"first_id":1}` · `101` · `200` · `400` · `400` · `0`.

- [ ] **Step 4: Commit**

```bash
git add crates/customer-contact-service
git commit -m "feat: customer-contact-service readAll endpoint"
```

---

### Task 7: customer-identification-service

**Files:**
- Create: `crates/customer-identification-service/Cargo.toml`
- Create: `crates/customer-identification-service/src/main.rs`
- Create: `crates/customer-identification-service/src/domain.rs`
- Create: `crates/customer-identification-service/src/repository.rs`
- Create: `crates/customer-identification-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1.
- Produces: `customer-identification-service` binary, port 3006, route `/customer-identifications`.

- [ ] **Step 1: Create the crate files**

`crates/customer-identification-service/Cargo.toml`:

```toml
[package]
name = "customer-identification-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/customer-identification-service/src/domain.rs`:

```rust
use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "id_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum IdType {
    Passport,
    NationalId,
    DriversLicense,
    TaxId,
    Ssn,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerIdentification {
    pub identification_id: i64,
    pub party_id: i64,
    pub id_type: IdType,
    pub id_number: String,
    pub issuing_country: String,
    pub issuing_authority: Option<String>,
    pub issue_date: Option<NaiveDate>,
    pub expiry_date: Option<NaiveDate>,
    pub is_primary: bool,
}
```

`crates/customer-identification-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CustomerIdentification;

/// Fetch one page of customer identifications plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CustomerIdentification>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CustomerIdentification>(
        "SELECT identification_id, party_id, id_type, id_number, issuing_country, \
         issuing_authority, issue_date, expiry_date, is_primary \
         FROM customer_identifications ORDER BY identification_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM customer_identifications")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/customer-identification-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CustomerIdentification, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/customer-identifications", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CustomerIdentification>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/customer-identification-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("customer-identification-service");
    let settings = Settings::load(3006)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p customer-identification-service && cargo clippy -p customer-identification-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/customer-identification-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3006/customer-identifications?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].identification_id}'
curl -s "http://localhost:3006/customer-identifications?page=2&page_size=100" | jq '.data[0].identification_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3006/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3006/customer-identifications?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3006/customer-identifications?page_size=101"
curl -s "http://localhost:3006/customer-identifications?page=11" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":1000,"pages":10,"first_id":1}` · `101` · `200` · `400` · `400` · `0`. Also confirm raw JSON shows `"id_type":"PASSPORT"` / `"TAX_ID"`.

- [ ] **Step 4: Commit**

```bash
git add crates/customer-identification-service
git commit -m "feat: customer-identification-service readAll endpoint"
```

---

### Task 8: customer-employment-service

**Files:**
- Create: `crates/customer-employment-service/Cargo.toml`
- Create: `crates/customer-employment-service/src/main.rs`
- Create: `crates/customer-employment-service/src/domain.rs`
- Create: `crates/customer-employment-service/src/repository.rs`
- Create: `crates/customer-employment-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1; `bigdecimal::BigDecimal` (workspace dep) for `DECIMAL(18,2)`.
- Produces: `customer-employment-service` binary, port 3007, route `/customer-employment`.

- [ ] **Step 1: Create the crate files**

`crates/customer-employment-service/Cargo.toml`:

```toml
[package]
name = "customer-employment-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
bigdecimal.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/customer-employment-service/src/domain.rs`:

```rust
use bigdecimal::BigDecimal;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "employment_status_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EmploymentStatus {
    Employed,
    SelfEmployed,
    Unemployed,
    Retired,
    Student,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerEmployment {
    pub employment_id: i64,
    pub party_id: i64,
    pub employment_status: EmploymentStatus,
    pub employer_name: Option<String>,
    pub occupation: Option<String>,
    pub industry_sector: Option<String>,
    pub annual_income: Option<BigDecimal>,
    pub income_currency: String,
    pub source_of_wealth: String,
}
```

`crates/customer-employment-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CustomerEmployment;

/// Fetch one page of customer employment rows plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CustomerEmployment>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CustomerEmployment>(
        "SELECT employment_id, party_id, employment_status, employer_name, occupation, \
         industry_sector, annual_income, income_currency, source_of_wealth \
         FROM customer_employment ORDER BY employment_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM customer_employment")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/customer-employment-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CustomerEmployment, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/customer-employment", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CustomerEmployment>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/customer-employment-service/src/main.rs`:

```rust
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p customer-employment-service && cargo clippy -p customer-employment-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/customer-employment-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3007/customer-employment?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].employment_id}'
curl -s "http://localhost:3007/customer-employment?page=2&page_size=100" | jq '.data[0].employment_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3007/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3007/customer-employment?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3007/customer-employment?page_size=101"
curl -s "http://localhost:3007/customer-employment?page=9" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":800,"pages":8,"first_id":1}` · `101` · `200` · `400` · `400` · `0`. Also confirm raw JSON shows `"annual_income"` as a JSON number (e.g. `123456.00`).

- [ ] **Step 4: Commit**

```bash
git add crates/customer-employment-service
git commit -m "feat: customer-employment-service readAll endpoint"
```

---

### Task 9: customer-kyc-service

**Files:**
- Create: `crates/customer-kyc-service/Cargo.toml`
- Create: `crates/customer-kyc-service/src/main.rs`
- Create: `crates/customer-kyc-service/src/domain.rs`
- Create: `crates/customer-kyc-service/src/repository.rs`
- Create: `crates/customer-kyc-service/src/handler.rs`

**Interfaces:**
- Consumes: `common` API from Task 1.
- Produces: `customer-kyc-service` binary, port 3008, route `/customer-kyc`.

- [ ] **Step 1: Create the crate files**

`crates/customer-kyc-service/Cargo.toml`:

```toml
[package]
name = "customer-kyc-service"
version = "0.1.0"
edition.workspace = true

[dependencies]
anyhow.workspace = true
axum.workspace = true
chrono.workspace = true
common.workspace = true
serde.workspace = true
serde_json.workspace = true
sqlx.workspace = true
tokio.workspace = true
tower-http.workspace = true
tracing.workspace = true
```

`crates/customer-kyc-service/src/domain.rs`:

```rust
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "kyc_status_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum KycStatus {
    Pending,
    Approved,
    Rejected,
    ReKycRequired,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "risk_rating_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RiskRating {
    Low,
    Medium,
    High,
    Prohibited,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerKyc {
    pub kyc_id: i64,
    pub party_id: i64,
    pub kyc_status: KycStatus,
    pub risk_rating: RiskRating,
    pub is_pep: bool,
    pub pep_details: Option<String>,
    pub sanctions_check_status: String,
    pub last_review_date: Option<DateTime<Utc>>,
    pub next_review_date: Option<DateTime<Utc>>,
}
```

`crates/customer-kyc-service/src/repository.rs`:

```rust
use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CustomerKyc;

/// Fetch one page of customer KYC rows plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CustomerKyc>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CustomerKyc>(
        "SELECT kyc_id, party_id, kyc_status, risk_rating, is_pep, pep_details, \
         sanctions_check_status, last_review_date, next_review_date \
         FROM customer_kyc ORDER BY kyc_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM customer_kyc")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
```

`crates/customer-kyc-service/src/handler.rs`:

```rust
use axum::{
    Json, Router,
    extract::{Query, State},
    response::IntoResponse,
    routing::get,
};
use common::{
    error::AppError,
    pagination::{Page, PageParams},
};
use sqlx::PgPool;
use tower_http::trace::TraceLayer;

use crate::{domain::CustomerKyc, repository};

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .route("/customer-kyc", get(read_all))
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn read_all(
    State(pool): State<PgPool>,
    Query(params): Query<PageParams>,
) -> Result<Json<Page<CustomerKyc>>, AppError> {
    let page = params.validate()?;
    let (rows, total) = repository::find_all(&pool, page).await?;
    Ok(Json(Page::new(rows, page, total)))
}
```

`crates/customer-kyc-service/src/main.rs`:

```rust
mod domain;
mod handler;
mod repository;

use common::{config::Settings, db, telemetry};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    telemetry::init("customer-kyc-service");
    let settings = Settings::load(3008)?;
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
    if tokio::signal::ctrl_c().await.is_ok() {
        tracing::info!("shutdown signal received, draining connections");
    }
}
```

- [ ] **Step 2: Build + clippy**

Run: `. "$HOME/.cargo/env" && cargo build -p customer-kyc-service && cargo clippy -p customer-kyc-service --all-targets -- -D warnings`
Expected: compiles, clippy clean.

- [ ] **Step 3: Live smoke test**

```bash
. "$HOME/.cargo/env"
export APP__DATABASE__URL="postgresql://harir@localhost:5432/bankdb"
./target/debug/customer-kyc-service & SVC_PID=$!
sleep 1
curl -s "http://localhost:3008/customer-kyc?page=1&page_size=100" | jq '{rows: (.data|length), page: .pagination.page, total: .pagination.total_records, pages: .pagination.total_pages, first_id: .data[0].kyc_id}'
curl -s "http://localhost:3008/customer-kyc?page=2&page_size=100" | jq '.data[0].kyc_id'
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3008/health"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3008/customer-kyc?page=0"
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3008/customer-kyc?page_size=101"
curl -s "http://localhost:3008/customer-kyc?page=11" | jq '.data | length'
kill $SVC_PID
```

Expected, in order: `{"rows":100,"page":1,"total":1000,"pages":10,"first_id":1}` · `101` · `200` · `400` · `400` · `0`. Also confirm raw JSON shows `"kyc_status":"APPROVED"`, `"risk_rating":"LOW"|"MEDIUM"`.

- [ ] **Step 4: Commit**

```bash
git add crates/customer-kyc-service
git commit -m "feat: customer-kyc-service readAll endpoint"
```

---

### Task 10: Full workspace gate + end-to-end verification

**Files:**
- Create: `scripts/verify.sh`

**Interfaces:**
- Consumes: all 8 service binaries in `target/debug/`.
- Produces: repeatable one-command verification of the whole deliverable.

- [ ] **Step 1: Create the verification script**

Create `scripts/verify.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

export APP__DATABASE__URL="${APP__DATABASE__URL:-postgresql://harir@localhost:5432/bankdb}"

cargo build --workspace

services=(
    "party-service 3001 parties party_id 1000 10"
    "individual-profile-service 3002 individual-profiles individual_id 800 8"
    "corporate-profile-service 3003 corporate-profiles corporate_id 200 2"
    "customer-address-service 3004 customer-addresses address_id 1000 10"
    "customer-contact-service 3005 customer-contacts contact_id 1000 10"
    "customer-identification-service 3006 customer-identifications identification_id 1000 10"
    "customer-employment-service 3007 customer-employment employment_id 800 8"
    "customer-kyc-service 3008 customer-kyc kyc_id 1000 10"
)

fail=0
for entry in "${services[@]}"; do
    read -r name port route pk total pages <<< "$entry"
    echo "=== $name (port $port, /$route) ==="
    ./target/debug/"$name" > /tmp/"$name".log 2>&1 &
    pid=$!
    sleep 1

    check() {
        local desc="$1" expected="$2" actual="$3"
        if [[ "$expected" == "$actual" ]]; then
            echo "  PASS: $desc ($actual)"
        else
            echo "  FAIL: $desc (expected $expected, got $actual)"
            fail=1
        fi
    }

    p1=$(curl -s "http://localhost:$port/$route?page=1&page_size=100")
    p2=$(curl -s "http://localhost:$port/$route?page=2&page_size=100")
    check "page 1 row count"        "100"    "$(jq '.data | length' <<< "$p1")"
    check "page 1 metadata"         "$total" "$(jq '.pagination.total_records' <<< "$p1")"
    check "page 1 total pages"      "$pages" "$(jq '.pagination.total_pages' <<< "$p1")"
    check "page 1 first pk"         "1"      "$(jq ".data[0].$pk" <<< "$p1")"
    check "page 2 first pk"         "101"    "$(jq ".data[0].$pk" <<< "$p2")"
    check "page 2 row count"        "100"    "$(jq '.data | length' <<< "$p2")"
    check "beyond-last page empty"  "0"      "$(curl -s "http://localhost:$port/$route?page=$((pages + 1))" | jq '.data | length')"
    check "health 200"              "200"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/health")"
    check "page=0 rejected"         "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page=0")"
    check "page_size=101 rejected"  "400"    "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$port/$route?page_size=101")"

    kill "$pid"
    wait "$pid" 2>/dev/null || true
done

if [[ $fail -ne 0 ]]; then
    echo "VERIFICATION FAILED"
    exit 1
fi
echo "ALL SERVICES VERIFIED"
```

Then: `chmod +x scripts/verify.sh`

- [ ] **Step 2: Run all workspace quality gates**

Run: `. "$HOME/.cargo/env" && cargo fmt --all -- --check && cargo clippy --all-targets --all-features -- -D warnings && cargo test --workspace`
Expected: fmt clean, clippy clean, all 7 unit tests pass.

- [ ] **Step 3: Run the end-to-end verification**

Run: `. "$HOME/.cargo/env" && bash scripts/verify.sh`
Expected: `ALL SERVICES VERIFIED` with 10 PASS lines per service (80 total).

- [ ] **Step 4: Commit**

```bash
git add scripts/verify.sh
git commit -m "test: end-to-end verification script for all services"
```

---

## Self-Review Results

**Spec coverage:** §2 table→service map → Tasks 2–9. §3 workspace → Task 1 + per-task file layout. §4 API contract → handlers + smoke checks + verify.sh. §5 data layer (type mappings, enum handling) → per-task `domain.rs`/`repository.rs`. §6 config → `common/src/config.rs`. §7 cross-cutting (errors, telemetry, shutdown, validation) → Task 1 files + per-task `main.rs`. §9 testing → Task 1 unit tests, per-task smoke, Task 10 gates. All covered.

**Placeholder scan:** none — every code step contains complete code.

**Type consistency:** `PageParams::validate`, `ValidatedPage{limit,offset}`, `Page::new(Vec<T>, ValidatedPage, u64)`, `Settings::load(u16)`, `create_pool(&str)`, `telemetry::init(&'static str)`, per-service `find_all(&PgPool, ValidatedPage) -> Result<(Vec<T>, u64), sqlx::Error>`, `router(PgPool) -> Router` — identical across all tasks.
