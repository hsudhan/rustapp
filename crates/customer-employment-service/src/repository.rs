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
