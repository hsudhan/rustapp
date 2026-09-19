# Rustapp — Banking Customer Master Microservices

A high-performance, async Rust microservices workspace implementing a **Banking Customer Master**. It supports retail (individual) and corporate customers with multi-address, contacts, identifications, employment, and KYC/compliance data — each domain exposed as its own independently deployable HTTP service.

Built with:

- **[tokio](https://tokio.rs)** — async runtime (multi-thread)
- **[axum](https://docs.rs/axum)** — web framework
- **[sqlx](https://docs.rs/sqlx)** — async PostgreSQL access (compile-time-friendly, runtime queries)
- **[tracing](https://docs.rs/tracing)** + `tracing-subscriber` — structured JSON logging
- **[config](https://docs.rs/config)** — environment-driven configuration (`APP__*` variables)
- **`thiserror` / `anyhow`** — structured error handling

---

## Table of Contents

1. [Architecture](#architecture)
2. [Services & Ports](#services--ports)
3. [Prerequisites](#prerequisites)
4. [Database Setup (DDL & DML)](#database-setup-ddl--dml)
5. [Configuration](#configuration)
6. [Build](#build)
7. [Run](#run)
8. [API Reference](#api-reference)
9. [Verification & Testing](#verification--testing)
10. [Code Quality (Lint & Format)](#code-quality-lint--format)
11. [Useful Cargo Commands Reference](#useful-cargo-commands-reference)
12. [Troubleshooting](#troubleshooting)
13. [Project Structure](#project-structure)

---

## Architecture

This is a Cargo workspace (`resolver = "3"`, Rust edition **2024**) containing a shared `common` library crate and 8 microservice binary crates. Each service follows a layered design:

```
main.rs        → entry point: telemetry init, config load, DB pool, graceful shutdown
handler.rs     → axum router, HTTP transport (query extraction, JSON responses)
domain.rs      → domain models (serde-serializable entities)
repository.rs  → data access (sqlx queries against PostgreSQL)
```

The `common` crate provides shared infrastructure:

| Module                | Purpose                                                              |
| --------------------- | -------------------------------------------------------------------- |
| `common::config`      | `Settings` loaded from `APP__*` env vars; DB URL redacted in logs    |
| `common::db`          | `sqlx::PgPool` creation                                              |
| `common::pagination`  | `page` / `page_size` validation (max page size = 100), envelope type |
| `common::error`       | Centralized `AppError` → HTTP status mapping                         |
| `common::telemetry`   | JSON tracing subscriber initialization                               |

Every service exposes:

- `GET /<resource>` — paginated list endpoint
- `GET /health` — liveness probe (returns `200 OK`)

All services handle `SIGINT`/`SIGTERM` for graceful shutdown.

---

## Services & Ports

| Service                          | Default Port | List Endpoint                | Table                    | Seeded Rows |
| -------------------------------- | ------------ | ---------------------------- | ------------------------ | ----------- |
| `party-service`                  | 3001         | `GET /parties`               | `parties`                | 1000        |
| `individual-profile-service`     | 3002         | `GET /individual-profiles`   | `individual_profiles`    | 800         |
| `corporate-profile-service`      | 3003         | `GET /corporate-profiles`    | `corporate_profiles`     | 200         |
| `customer-address-service`       | 3004         | `GET /customer-addresses`    | `customer_addresses`     | 1000        |
| `customer-contact-service`       | 3005         | `GET /customer-contacts`     | `customer_contacts`      | 1000        |
| `customer-identification-service`| 3006         | `GET /customer-identifications` | `customer_identifications` | 1000    |
| `customer-employment-service`    | 3007         | `GET /customer-employment`   | `customer_employment`    | 800         |
| `customer-kyc-service`           | 3008         | `GET /customer-kyc`          | `customer_kyc`           | 1000        |

---

## Prerequisites

### 1. Rust toolchain (1.85+)

The workspace uses Rust **edition 2024**, which requires Rust 1.85 or newer. Install via [rustup](https://rustup.rs):

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
rustup default stable
rustc --version   # verify >= 1.85
```

### 2. PostgreSQL (13+)

You need a running PostgreSQL server **and** the `psql` client.

- **macOS (Homebrew):**

  ```bash
  brew install postgresql@16
  brew services start postgresql@16
  ```

- **Ubuntu/Debian:**

  ```bash
  sudo apt update && sudo apt install postgresql postgresql-client
  sudo systemctl enable --now postgresql
  ```

- **Docker (alternative, no local install):**

  ```bash
  docker run --name bankdb-postgres \
    -e POSTGRES_PASSWORD=postgres \
    -p 5432:5432 -d postgres:16
  ```

### 3. Utility tools

- `curl` — for hitting the API endpoints (preinstalled on macOS/Linux).
- `jq` — required by `scripts/verify.sh` for JSON assertions:

  ```bash
  brew install jq        # macOS
  sudo apt install jq    # Ubuntu/Debian
  ```

---

## Database Setup (DDL & DML)

The repository ships with two SQL scripts at the project root:

- **`DDL.sql`** — drops (if present) and recreates the full schema: 9 enum types + 8 tables (`parties`, `individual_profiles`, `corporate_profiles`, `customer_addresses`, `customer_contacts`, `customer_identifications`, `customer_employment`, `customer_kyc`) with indexes, constraints, and comments.
- **`DML.sql`** — seeds synthetic demo data: 1000 parties (800 individuals / 200 corporates) plus related addresses, contacts, identifications, employment, and KYC records.

> ⚠️ `DDL.sql` is **destructive** — it drops and recreates all tables. Do not run it against a database containing data you care about.

### Step 1 — Create the database

```bash
createdb bankdb
```

or via `psql`:

```bash
psql -h localhost -U "$USER" -d postgres -c "CREATE DATABASE bankdb;"
```

### Step 2 — Run the DDL (schema) script

```bash
psql -h localhost -U "$USER" -d bankdb -f DDL.sql
```

### Step 3 — Run the DML (seed data) script

```bash
psql -h localhost -U "$USER" -d bankdb -f DML.sql
```

### Step 4 — Verify the data

```bash
psql -h localhost -U "$USER" -d bankdb -c "
SELECT 'parties' AS table_name, COUNT(*) FROM parties
UNION ALL SELECT 'individual_profiles', COUNT(*) FROM individual_profiles
UNION ALL SELECT 'corporate_profiles', COUNT(*) FROM corporate_profiles
UNION ALL SELECT 'customer_addresses', COUNT(*) FROM customer_addresses
UNION ALL SELECT 'customer_contacts', COUNT(*) FROM customer_contacts
UNION ALL SELECT 'customer_identifications', COUNT(*) FROM customer_identifications
UNION ALL SELECT 'customer_employment', COUNT(*) FROM customer_employment
UNION ALL SELECT 'customer_kyc', COUNT(*) FROM customer_kyc
ORDER BY 1;"
```

Expected counts: `parties=1000`, `individual_profiles=800`, `corporate_profiles=200`, `customer_addresses=1000`, `customer_contacts=1000`, `customer_identifications=1000`, `customer_employment=800`, `customer_kyc=1000`.

> **Using Docker Postgres?** Run the scripts with:
>
> ```bash
> docker exec -i bankdb-postgres psql -U postgres -d bankdb < DDL.sql
> docker exec -i bankdb-postgres psql -U postgres -d bankdb < DML.sql
> ```
>
> (create the DB first: `docker exec -it bankdb-postgres createdb -U postgres bankdb`)

---

## Configuration

Configuration is driven entirely by environment variables with the `APP__` prefix (double underscore = nesting separator).

| Variable             | Required | Default                | Description                              |
| -------------------- | -------- | ---------------------- | ---------------------------------------- |
| `APP__DATABASE__URL` | ✅ Yes   | —                      | PostgreSQL connection string             |
| `APP__SERVER__HOST`  | No       | `0.0.0.0`              | Bind host                                |
| `APP__SERVER__PORT`  | No       | service-specific (3001–3008) | Bind port (see [Services & Ports](#services--ports)) |

Set the database URL before running anything:

```bash
export APP__DATABASE__URL="postgresql://$USER@localhost:5432/bankdb"
```

With a password / Docker Postgres:

```bash
export APP__DATABASE__URL="postgresql://postgres:postgres@localhost:5432/bankdb"
```

To run a service on a non-default port:

```bash
APP__SERVER__PORT=4001 cargo run -p party-service
```

> The database URL is automatically **redacted** in logs (`<redacted>`), so secrets never leak into log output.

---

## Build

```bash
# Debug build — entire workspace (all 8 services + common)
cargo build --workspace

# Debug build — a single service
cargo build -p party-service

# Release build (optimized) — entire workspace
cargo build --release --workspace

# Release build — a single service
cargo build --release -p party-service

# Type-check only (fastest, no codegen)
cargo check --workspace
```

Binaries are produced at:

- Debug: `./target/debug/<service-name>`
- Release: `./target/release/<service-name>`

---

## Run

### Run a single service

```bash
export APP__DATABASE__URL="postgresql://$USER@localhost:5432/bankdb"

cargo run -p party-service                  # port 3001
cargo run -p individual-profile-service     # port 3002
cargo run -p corporate-profile-service      # port 3003
cargo run -p customer-address-service       # port 3004
cargo run -p customer-contact-service       # port 3005
cargo run -p customer-identification-service# port 3006
cargo run -p customer-employment-service    # port 3007
cargo run -p customer-kyc-service           # port 3008
```

Or run the compiled binary directly (after `cargo build --workspace`):

```bash
./target/debug/party-service
```

### Run all services at once (helper script)

`startapps.sh` exports the database URL and launches all 8 services in the background with `nohup`:

```bash
./startapps.sh
```

Logs for each service go to `nohup.out`. To stop everything started this way:

```bash
pkill -f 'target/debug/.*-service'
```

### Control log verbosity

Logging uses `tracing` with an env filter (JSON output):

```bash
RUST_LOG=info cargo run -p party-service
RUST_LOG=debug,sqlx=warn cargo run -p party-service
```

---

## API Reference

### `GET /<resource>` — paginated list

Query parameters:

| Parameter   | Type    | Default | Constraints       | Error on violation |
| ----------- | ------- | ------- | ----------------- | ------------------ |
| `page`      | integer | `1`     | `>= 1`            | `400` if `0`       |
| `page_size` | integer | `100`   | `1 ..= 100`       | `400` if `0` or `> 100` |

Response envelope:

```json
{
  "data": [ /* array of resource objects */ ],
  "pagination": {
    "page": 1,
    "page_size": 100,
    "total_records": 1000,
    "total_pages": 10
  }
}
```

### `GET /health` — liveness

Returns `200 OK` when the service is up.

### Examples

```bash
# First page of parties (100 records)
curl -s "http://localhost:3001/parties" | jq

# Second page, 25 records per page
curl -s "http://localhost:3001/parties?page=2&page_size=25" | jq

# KYC records
curl -s "http://localhost:3008/customer-kyc?page=1&page_size=10" | jq

# Health check
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:3001/health"   # → 200

# Invalid pagination → 400 Bad Request
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:3001/parties?page=0"
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:3001/parties?page_size=101"
```

---

## Verification & Testing

### Automated end-to-end verification

`scripts/verify.sh` builds the whole workspace, boots each of the 8 services one at a time, and asserts (via `curl` + `jq`):

- page 1 / page 2 row counts and pagination metadata (total records, total pages)
- primary keys are numeric and strictly increasing across pages
- beyond-last page returns an empty `data` array
- `/health` returns `200`
- `page=0` and `page_size=101` are rejected with `400`
- all enum fields contain only valid enum values

Run it (requires `jq` and a seeded `bankdb`):

```bash
export APP__DATABASE__URL="postgresql://$USER@localhost:5432/bankdb"
./scripts/verify.sh
```

Expected final output: `ALL SERVICES VERIFIED`.

### Unit tests

```bash
# All tests in the workspace
cargo test --workspace

# Tests for a single crate
cargo test -p common
cargo test -p party-service
```

---

## Code Quality (Lint & Format)

Per project standards, **zero Clippy warnings** are allowed and code must be `rustfmt`-clean:

```bash
# Lint (treat warnings as errors — must pass clean)
cargo clippy --all-targets --all-features -- -D warnings

# Format all code
cargo fmt --all

# Check formatting without modifying files (CI mode)
cargo fmt --all -- --check
```

Optional supply-chain checks (install once via `cargo install cargo-audit cargo-deny`):

```bash
cargo audit   # known-vulnerability scan of dependencies
cargo deny check
```

---

## Useful Cargo Commands Reference

| Task                              | Command                                                        |
| --------------------------------- | -------------------------------------------------------------- |
| Check (fast type-check)           | `cargo check --workspace`                                      |
| Build (debug)                     | `cargo build --workspace`                                      |
| Build (release)                   | `cargo build --release --workspace`                            |
| Run a service                     | `cargo run -p <service-name>`                                  |
| Run with release optimizations    | `cargo run --release -p <service-name>`                        |
| Run tests                         | `cargo test --workspace`                                       |
| Lint                              | `cargo clippy --all-targets --all-features -- -D warnings`     |
| Format                            | `cargo fmt --all`                                              |
| Clean build artifacts             | `cargo clean`                                                  |
| Update dependencies               | `cargo update`                                                 |
| Show dependency tree              | `cargo tree` or `cargo tree -p party-service`                  |
| Build docs and open in browser    | `cargo doc --workspace --open`                                 |
| Audit dependencies                | `cargo audit`                                                  |

---

## Troubleshooting

**`error: APP__DATABASE__URL ...` / config error on startup**
You forgot to export the database URL. See [Configuration](#configuration).

**`error connecting to server: Connection refused (os error 61)`**
PostgreSQL is not running. Start it with `brew services start postgresql@16` (macOS), `sudo systemctl start postgresql` (Linux), or start your Docker container.

**`relation "parties" does not exist`**
The schema was never created. Run the DDL script: `psql -d bankdb -f DDL.sql` (see [Database Setup](#database-setup-ddl--dml)).

**Endpoints return empty `data` arrays**
Schema exists but isn't seeded. Run: `psql -d bankdb -f DML.sql`.

**`Address already in use (os error 48)`**
Another instance of the service (or something else) is bound to that port. Kill it (`pkill -f party-service`) or override the port: `APP__SERVER__PORT=4001 cargo run -p party-service`.

**`cargo`/`rustc` not found in a new shell**
Load the rustup environment: `source "$HOME/.cargo/env"`.

**`scripts/verify.sh` fails immediately**
Ensure `jq` is installed, `APP__DATABASE__URL` is exported, the database is seeded, and no stray service instances are already holding ports 3001–3008.

---

## Project Structure

```text
.
├── Cargo.toml                 # Workspace manifest (shared deps, edition 2024)
├── Cargo.lock
├── DDL.sql                    # Schema: enums, tables, indexes, constraints
├── DML.sql                    # Seed data: 1000 parties + related records
├── startapps.sh               # Launch all 8 services in background (nohup)
├── scripts/
│   └── verify.sh              # End-to-end verification of all services
├── docs/
└── crates/
    ├── common/                # Shared library: config, db pool, pagination,
    │                          #   error types, telemetry
    ├── party-service/         # src/{main,handler,domain,repository}.rs
    ├── individual-profile-service/
    ├── corporate-profile-service/
    ├── customer-address-service/
    ├── customer-contact-service/
    ├── customer-identification-service/
    ├── customer-employment-service/
    └── customer-kyc-service/
```

Each service crate mirrors the same layout:

```text
src/
├── main.rs        # bootstrap: telemetry → config → pool → router → serve
├── handler.rs     # axum routes, query-param extraction, JSON responses
├── domain.rs      # entity structs (serde)
└── repository.rs  # sqlx queries
```

---

## Quick Start (TL;DR)

```bash
# 1. Install prerequisites: Rust (rustup), PostgreSQL, jq

# 2. Create and seed the database
createdb bankdb
psql -d bankdb -f DDL.sql
psql -d bankdb -f DML.sql

# 3. Point the app at the database
export APP__DATABASE__URL="postgresql://$USER@localhost:5432/bankdb"

# 4. Build and run
cargo build --workspace
cargo run -p party-service

# 5. Try it
curl -s "http://localhost:3001/parties?page=1&page_size=10" | jq

# 6. (Optional) verify everything end-to-end
./scripts/verify.sh
```
