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
