# Banking Customer Master Microservices — Design

**Date:** 2026-09-08
**Status:** Approved (in-chat), pending spec review
**Source schema:** `DDL.sql` (PostgreSQL, Banking Customer Master)

## 1. Goal

One read-only REST/JSON microservice per table in `DDL.sql` (8 tables → 8 services).
Each service exposes a `readAll` endpoint: HTTP GET returning 100 records per page,
offset-paginated. Stack per `claude.md`: tokio, axum, sqlx, tracing, config, thiserror.

## 2. Tables and services

| Service crate | Table | Default port |
|---|---|---|
| `party-service` | `parties` | 3001 |
| `individual-profile-service` | `individual_profiles` | 3002 |
| `corporate-profile-service` | `corporate_profiles` | 3003 |
| `customer-address-service` | `customer_addresses` | 3004 |
| `customer-contact-service` | `customer_contacts` | 3005 |
| `customer-identification-service` | `customer_identifications` | 3006 |
| `customer-employment-service` | `customer_employment` | 3007 |
| `customer-kyc-service` | `customer_kyc` | 3008 |

## 3. Workspace structure

```
Cargo.toml                    # workspace root, pinned dependency versions
crates/
  common/                     # shared library
    src/lib.rs                # re-exports
    src/config.rs             # Settings via `config` crate, APP__* env overrides
    src/db.rs                 # sqlx PgPool construction
    src/pagination.rs         # PageParams extractor + Page<T> envelope
    src/error.rs              # AppError (thiserror) -> HTTP/JSON mapping
    src/telemetry.rs          # tracing-subscriber JSON init
  <name>-service/
    Cargo.toml
    src/main.rs               # telemetry, config, pool, router, serve + graceful shutdown
    src/domain.rs             # row struct (FromRow, Serialize) + PG enum types
    src/repository.rs         # parameterized SELECT ... LIMIT/OFFSET + COUNT(*)
    src/handler.rs            # axum router: GET /<resource>, GET /health
```

## 4. API contract (all 8 services)

```
GET /<resource>?page=1&page_size=100
GET /health                     -> 200 {"status":"ok"}
```

- `page`: optional, default 1, must be >= 1 → 400 otherwise
- `page_size`: optional, default 100, 1..=100 → 400 otherwise
- Success response `200`:

```json
{
  "data": [ { "party_id": 1, "...": "..." } ],
  "pagination": { "page": 1, "page_size": 100, "total_records": 1000, "total_pages": 10 }
}
```

- Error response: `{ "error": "<message>" }` with 400 (validation) or 500 (database).
- A `page` beyond `total_pages` is valid → `200` with an empty `data` array and
  correct pagination metadata.

Resource paths: `/parties`, `/individual-profiles`, `/corporate-profiles`,
`/customer-addresses`, `/customer-contacts`, `/customer-identifications`,
`/customer-employment`, `/customer-kyc`.

## 5. Data layer

- Runtime-checked `sqlx::query_as` with `FromRow` derives — no live DB needed at build time.
- readAll query: `SELECT <cols> FROM <table> ORDER BY <pk> LIMIT $1 OFFSET $2`
  plus `SELECT COUNT(*) FROM <table>`; fully parameterized (no string-built SQL).
- Ordered by primary key for stable pagination.

Type mapping:
- `BIGSERIAL`/`BIGINT` → `i64`
- `VARCHAR`/`TEXT`/`CHAR(n)` → `String`
- `DATE` → `chrono::NaiveDate`
- `TIMESTAMP WITH TIME ZONE` → `chrono::DateTime<chrono::Utc>`
- `DECIMAL(18,2)` → `bigdecimal::BigDecimal`
- `BOOLEAN` → `bool`
- NULL columns → `Option<T>`
- PG enums → Rust enums via `sqlx::Type` + serde, JSON values identical to DB
  strings (`"IN"`, `"CORP"`, `"RE_KYC_REQUIRED"`, ...).

## 6. Configuration

- `config` crate; env overrides with prefix `APP__` (per claude.md).
- `APP__DATABASE__URL` (required, no default — secrets never hardcoded)
- `APP__SERVER__HOST` (default `0.0.0.0`), `APP__SERVER__PORT` (per-service default from §2)
- Connection string for local verification: `postgresql://harir@localhost:5432/bankdb`
  (passed via env var only, never committed to source).

## 7. Cross-cutting

- **Errors:** thiserror `AppError` in `common`; `IntoResponse` produces the JSON
  error body; sqlx errors logged with tracing, surfaced as generic 500 (no internals leak).
- **Telemetry:** `tracing-subscriber` JSON logs, one line per event; request spans via
  `tower-http` `TraceLayer`.
- **Shutdown:** graceful shutdown on SIGTERM/SIGINT via `tokio::signal`.
- **Validation:** explicit domain validation of pagination params in the extractor
  (reject, don't clamp) → 400 with message.

## 8. Out of scope (YAGNI)

getById/create/update/delete, authentication, rate limiting, Dockerfile,
migrations folder (schema owned externally by DDL.sql), docker-compose (DB already running).

## 9. Testing & verification

- Unit tests: pagination param validation (defaults, bounds, rejection).
- `cargo build`, `cargo clippy --all-targets --all-features -- -D warnings`, `cargo fmt --check`.
- Live verification against `bankdb`: start each service, request page 1 and page 2
  of each endpoint; assert 100 records/page, distinct PKs across pages, correct
  `total_records` (1000/800/200 per table) and `total_pages`.
