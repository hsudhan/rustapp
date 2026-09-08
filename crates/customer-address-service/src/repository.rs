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
