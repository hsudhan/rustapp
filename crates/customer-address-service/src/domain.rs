use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "address_type_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum AddressType {
    Residential,
    Mailing,
    Registered,
    Office,
    Billing,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerAddress {
    pub address_id: i64,
    pub party_id: i64,
    pub address_type: AddressType,
    pub address_line_1: String,
    pub address_line_2: Option<String>,
    pub city: String,
    pub state_province: Option<String>,
    pub postal_code: Option<String>,
    pub country_code: String,
    pub is_primary: bool,
    pub effective_from: NaiveDate,
    pub effective_to: Option<NaiveDate>,
}
