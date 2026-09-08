use chrono::NaiveDate;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, FromRow, Serialize)]
pub struct CorporateProfile {
    pub corporate_id: i64,
    pub party_id: i64,
    pub company_name: String,
    pub trade_name: Option<String>,
    pub registration_number: String,
    pub incorporation_date: NaiveDate,
    pub country_of_inc: String,
    pub industry_code: String,
    pub business_structure: String,
    pub tax_identification: String,
}
