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
