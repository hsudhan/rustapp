use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "contact_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ContactType {
    Mobile,
    Landline,
    WorkPhone,
    Email,
    Fax,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerContact {
    pub contact_id: i64,
    pub party_id: i64,
    pub contact_type: ContactType,
    pub country_dial_code: Option<String>,
    pub contact_value: String,
    pub is_primary: bool,
    pub is_verified: bool,
    pub opt_in_marketing: bool,
}
