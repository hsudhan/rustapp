use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::CorporateProfile;

/// Fetch one page of corporate profiles plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<CorporateProfile>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, CorporateProfile>(
        "SELECT corporate_id, party_id, company_name, trade_name, registration_number, \
         incorporation_date, country_of_inc, industry_code, business_structure, \
         tax_identification \
         FROM corporate_profiles ORDER BY corporate_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM corporate_profiles")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
