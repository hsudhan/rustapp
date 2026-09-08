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
