use common::pagination::ValidatedPage;
use sqlx::PgPool;

use crate::domain::IndividualProfile;

/// Fetch one page of individual profiles plus the total row count.
///
/// # Errors
/// Returns `sqlx::Error` on database failure.
pub async fn find_all(
    pool: &PgPool,
    page: ValidatedPage,
) -> Result<(Vec<IndividualProfile>, u64), sqlx::Error> {
    let rows = sqlx::query_as::<_, IndividualProfile>(
        "SELECT individual_id, party_id, title, first_name, middle_name, last_name, \
         preferred_name, date_of_birth, gender, marital_status, nationality, \
         citizenship_status, mother_maiden_name \
         FROM individual_profiles ORDER BY individual_id LIMIT $1 OFFSET $2",
    )
    .bind(page.limit())
    .bind(page.offset())
    .fetch_all(pool)
    .await?;

    let total = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM individual_profiles")
        .fetch_one(pool)
        .await?;

    Ok((rows, u64::try_from(total).unwrap_or(0)))
}
