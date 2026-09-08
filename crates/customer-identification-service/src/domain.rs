use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "id_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum IdType {
    Passport,
    NationalId,
    DriversLicense,
    TaxId,
    Ssn,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerIdentification {
    pub identification_id: i64,
    pub party_id: i64,
    pub id_type: IdType,
    pub id_number: String,
    pub issuing_country: String,
    pub issuing_authority: Option<String>,
    pub issue_date: Option<NaiveDate>,
    pub expiry_date: Option<NaiveDate>,
    pub is_primary: bool,
}
