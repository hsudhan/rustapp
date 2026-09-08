use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "kyc_status_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum KycStatus {
    Pending,
    Approved,
    Rejected,
    ReKycRequired,
}

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "risk_rating_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RiskRating {
    Low,
    Medium,
    High,
    Prohibited,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerKyc {
    pub kyc_id: i64,
    pub party_id: i64,
    pub kyc_status: KycStatus,
    pub risk_rating: RiskRating,
    pub is_pep: bool,
    pub pep_details: Option<String>,
    pub sanctions_check_status: String,
    pub last_review_date: Option<DateTime<Utc>>,
    pub next_review_date: Option<DateTime<Utc>>,
}
