use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "party_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum PartyType {
    In,
    Corp,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(
    type_name = "customer_segment_enum",
    rename_all = "SCREAMING_SNAKE_CASE"
)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CustomerSegment {
    Retail,
    Wealth,
    Sme,
    Corporate,
    Institutional,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(
    type_name = "customer_status_enum",
    rename_all = "SCREAMING_SNAKE_CASE"
)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CustomerStatus {
    Pending,
    Active,
    Inactive,
    Dormant,
    Suspended,
    Closed,
}

#[derive(Debug, FromRow, Serialize)]
pub struct Party {
    pub party_id: i64,
    pub party_type: PartyType,
    pub customer_segment: CustomerSegment,
    pub customer_status: CustomerStatus,
    pub onboarding_date: DateTime<Utc>,
    pub home_branch_id: String,
    pub preferred_language: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
