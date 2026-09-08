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
