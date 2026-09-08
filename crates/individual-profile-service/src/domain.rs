use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, FromRow, Serialize)]
pub struct IndividualProfile {
    pub individual_id: i64,
    pub party_id: i64,
    pub title: Option<String>,
    pub first_name: String,
    pub middle_name: Option<String>,
    pub last_name: String,
    pub preferred_name: Option<String>,
    pub date_of_birth: NaiveDate,
    pub gender: Option<String>,
    pub marital_status: Option<String>,
    pub nationality: String,
    pub citizenship_status: Option<String>,
    pub mother_maiden_name: Option<String>,
}
