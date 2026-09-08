use bigdecimal::BigDecimal;
use serde::Serialize;
use sqlx::FromRow;

#[derive(Debug, Clone, Copy, Serialize, sqlx::Type)]
#[sqlx(type_name = "employment_status_enum", rename_all = "SCREAMING_SNAKE_CASE")]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EmploymentStatus {
    Employed,
    SelfEmployed,
    Unemployed,
    Retired,
    Student,
}

#[derive(Debug, FromRow, Serialize)]
pub struct CustomerEmployment {
    pub employment_id: i64,
    pub party_id: i64,
    pub employment_status: EmploymentStatus,
    pub employer_name: Option<String>,
    pub occupation: Option<String>,
    pub industry_sector: Option<String>,
    pub annual_income: Option<BigDecimal>,
    pub income_currency: String,
    pub source_of_wealth: String,
}
