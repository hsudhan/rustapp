# Claude Code Instructions for Rust Microservice

This document serves as the standard context and instruction set for AI coding assistants (like Claude Code) working on this Rust microservice repository. Adhere strictly to these guidelines when generating, modifying, or reviewing code.

---

## 1. Project Overview & Architecture
This repository contains a high-performance, async Rust microservice built using modern idioms.
* **Core Framework:** `tokio` (runtime), `axum` (web framework) or `tonic` (gRPC).
* **Configuration:** `config` crate with environment variable overrides (`APP__*`).
* **Observability:** `tracing`, `tracing-subscriber`, structured JSON logs.
* **Error Handling:** `thiserror` for library/domain errors, `anyhow` for application-level context.
* **Database / State:** `sqlx` (async SQL), `redis` (caching/pubsub).

---

## 2. Folder Structure
```text
.
├── Cargo.toml
├── Cargo.lock
├── Dockerfile
├── README.md
├── configs/
│   ├── default.toml
│   └── local.toml
├── migrations/          # SQLx database migrations
└── src/
    ├── main.rs          # Entry point, telemetry setup, graceful shutdown
    ├── lib.rs           # Exposes app factory for integration testing
    ├── config.rs        # Settings parsing and validation
    ├── error.rs         # Centralized error types
    ├── telemetry.rs     # Tracing and metrics setup
    ├── domain/          # Pure business logic and domain models
    ├── services/        # Application use cases / business workflows
    ├── repositories/    # Data access layer (sqlx queries, redis clients)
    └── handlers/        # API transport layer (Axum routers, extractors, DTOs)
```

---

## 3. Coding & Naming Standards

### Rust Idioms & Style
* **Edition:** Rust 2024 (or 2021 where applicable).
* **Clippy:** Zero warnings allowed. Run `cargo clippy --all-targets --all-features -- -D warnings` on every change.
* **Formatting:** Standard `rustfmt` settings (enforced via CI).
* **Async/Await:** Use `async-trait` only when necessary; prefer native async functions in traits where Rust permits. Avoid blocking operations (`std::fs`, heavy CPU loops) on the Tokio runtime; offload via `tokio::task::spawn_blocking`.

### Naming Conventions
* **Crates, Modules, Files:** `snake_case` (e.g., `user_profile.rs`, `database_pool.rs`).
* **Types, Structs, Enums, Traits:** `PascalCase` (e.g., `UserRepository`, `AppError`).
* **Functions, Variables, Methods:** `snake_case` (e.g., `get_user_by_id`, `retry_count`).
* **Constants:** `SCREAMING_SNAKE_CASE` (e.g., `DEFAULT_TIMEOUT_SECS`).
* **DTOs / Request-Response Structs:** Suffix with purpose (e.g., `CreateUserRequest`, `UserResponseDto`).

---

## 4. Security Considerations & Requirements

* **Input Validation:** Never trust client input. Validate all DTO fields using `validator` derive macros or explicit domain validation logic before processing.
* **SQL Injection Prevention:** Always use parameterized queries via `sqlx` (`query!` or `$1, $2` binders). Never use string formatting or concatenation to build SQL queries.
* **Secret Management:** Hardcoded secrets, API keys, and connection strings are strictly prohibited. Load all secrets exclusively through environment variables or secure vault injections. Mask secrets in logs using `#[sensitive]` or custom `Debug` implementations.
* **Dependency Auditing:** Regularly run `cargo audit` and `cargo deny` to check for vulnerable dependencies and license compliance.
* **Rate Limiting & Timeouts:** All external HTTP calls and public endpoints must enforce strict timeouts (`tokio::time::timeout`) and rate-limiting to prevent DoS or resource exhaustion.

---

## 5. Core Commands

* **Build (Debug):** `cargo build`
* **Build (Release):** `cargo build --release`
* **Run Local:** `cargo run`
* **Run Tests:** `cargo test`
* **Run Lints (Clippy):** `cargo clippy --all-targets --all-features -- -D warnings`
* **Format Code:** `cargo fmt --all`
* **Database Migration Run:** `sqlx migrate run`
* **Database Migration Add:** `sqlx migrate add <migration_name>`
* **Audit Dependencies:** `cargo audit`

---

## 6. Gotchas & Rust-Specific Pitfalls

1. **Unintentional Blocking in Async Context:** Calling synchronous I/O or heavy computation inside an async handler will starve the Tokio worker threads. Use `tokio::task::spawn_blocking` for CPU-bound tasks or blocking blocking client libraries.
2. **Arc / Mutex Overuse:** Avoid wrapping everything in `Arc<Mutex<T>>` or `Arc<RwLock<T>>`. Design services around ownership transfer, message passing (`tokio::sync::mpsc`), or stateless repository patterns backed by connection pools (`sqlx::PgPool` is already thread-safe and cheaply clonable).
3. **Deadlocks with `tokio::sync::Mutex` vs `std::sync::Mutex`:** Across `.await` suspension points, standard `std::sync::MutexGuard` cannot be held because it is not `Send`. Always use `tokio::sync::Mutex` if a lock needs to cross an `.await` boundary, but be mindful of lock contention.
4. **Error Context Loss:** When returning errors from lower layers up to handlers, avoid generic string errors. Use `thiserror` for structured domain errors and attach context with `anyhow::Context` at application boundaries to preserve stack traces and error chains.
5. **Lifetimes in Axum Extractors:** Be careful when writing custom Axum extractors dealing with borrowed data. Prefer owned types (`String`, `Uuid`) in request DTOs over lifetimes tied to request headers or payloads unless performance profiling explicitly demands zero-copy parsing.
