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
