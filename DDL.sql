-- ====================================================================
-- BANKING CUSTOMER MASTER DATABASE SCHEMA (POSTGRESQL)
-- ====================================================================
-- Description: Comprehensive, normalized DDL script for a banking 
--              Customer Master supporting Retail & Corporate clients,
--              multi-address, contacts, KYC, and compliance.
-- ====================================================================

-- Drop existing tables if re-running script (in reverse order of dependencies)
DROP TABLE IF EXISTS customer_kyc CASCADE;
DROP TABLE IF EXISTS customer_employment CASCADE;
DROP TABLE IF EXISTS customer_identifications CASCADE;
DROP TABLE IF EXISTS customer_contacts CASCADE;
DROP TABLE IF EXISTS customer_addresses CASCADE;
DROP TABLE IF EXISTS corporate_profiles CASCADE;
DROP TABLE IF EXISTS individual_profiles CASCADE;
DROP TABLE IF EXISTS parties CASCADE;

-- Drop custom types if they exist
DROP TYPE IF EXISTS party_type_enum CASCADE;
DROP TYPE IF EXISTS customer_segment_enum CASCADE;
DROP TYPE IF EXISTS customer_status_enum CASCADE;
DROP TYPE IF EXISTS address_type_enum CASCADE;
DROP TYPE IF EXISTS contact_type_enum CASCADE;
DROP TYPE IF EXISTS id_type_enum CASCADE;
DROP TYPE IF EXISTS employment_status_enum CASCADE;
DROP TYPE IF EXISTS risk_rating_enum CASCADE;
DROP TYPE IF EXISTS kyc_status_enum CASCADE;

-- ====================================================================
-- CREATE ENUMERATED TYPES FOR DATA INTEGRITY
-- ====================================================================

CREATE TYPE party_type_enum AS ENUM ('IN', 'CORP');
CREATE TYPE customer_segment_enum AS ENUM ('RETAIL', 'WEALTH', 'SME', 'CORPORATE', 'INSTITUTIONAL');
CREATE TYPE customer_status_enum AS ENUM ('PENDING', 'ACTIVE', 'INACTIVE', 'DORMANT', 'SUSPENDED', 'CLOSED');
CREATE TYPE address_type_enum AS ENUM ('RESIDENTIAL', 'MAILING', 'REGISTERED', 'OFFICE', 'BILLING');
CREATE TYPE contact_type_enum AS ENUM ('MOBILE', 'LANDLINE', 'WORK_PHONE', 'EMAIL', 'FAX');
CREATE TYPE id_type_enum AS ENUM ('PASSPORT', 'NATIONAL_ID', 'DRIVERS_LICENSE', 'TAX_ID', 'SSN');
CREATE TYPE employment_status_enum AS ENUM ('EMPLOYED', 'SELF_EMPLOYED', 'UNEMPLOYED', 'RETIRED', 'STUDENT');
CREATE TYPE risk_rating_enum AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'PROHIBITED');
CREATE TYPE kyc_status_enum AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'RE_KYC_REQUIRED');

-- ====================================================================
-- 1. PARTIES (Core Base Table)
-- ====================================================================
CREATE TABLE parties (
    party_id BIGSERIAL PRIMARY KEY,
    party_type party_type_enum NOT NULL,
    customer_segment customer_segment_enum NOT NULL,
    customer_status customer_status_enum NOT NULL DEFAULT 'PENDING',
    onboarding_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    home_branch_id VARCHAR(20) NOT NULL,
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'en',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE parties IS 'Core central entity table for all banking customers (polymorphic base)';
COMMENT ON COLUMN parties.party_id IS 'Unique primary key identifier for the party';
COMMENT ON COLUMN parties.party_type IS 'IN for Individual, CORP for Corporate entity';


-- ====================================================================
-- 2. INDIVIDUAL PROFILES
-- ====================================================================
CREATE TABLE individual_profiles (
    individual_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL UNIQUE REFERENCES parties(party_id) ON DELETE CASCADE,
    title VARCHAR(20) NULL,
    first_name VARCHAR(100) NOT NULL,
    middle_name VARCHAR(100) NULL,
    last_name VARCHAR(100) NOT NULL,
    preferred_name VARCHAR(100) NULL,
    date_of_birth DATE NOT NULL,
    gender VARCHAR(20) NULL,
    marital_status VARCHAR(20) NULL,
    nationality CHAR(3) NOT NULL, -- ISO 3166-1 alpha-3
    citizenship_status VARCHAR(30) NULL,
    mother_maiden_name VARCHAR(100) NULL
);

COMMENT ON TABLE individual_profiles IS 'Biographical and personal attributes specifically for human customers';


-- ====================================================================
-- 3. CORPORATE PROFILES
-- ====================================================================
CREATE TABLE corporate_profiles (
    corporate_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL UNIQUE REFERENCES parties(party_id) ON DELETE CASCADE,
    company_name VARCHAR(255) NOT NULL,
    trade_name VARCHAR(255) NULL,
    registration_number VARCHAR(100) NOT NULL UNIQUE,
    incorporation_date DATE NOT NULL,
    country_of_inc CHAR(3) NOT NULL, -- ISO 3166-1 alpha-3
    industry_code VARCHAR(20) NOT NULL, -- ISIC or NAICS code
    business_structure VARCHAR(50) NOT NULL, -- LLC, Corporation, Partnership, etc.
    tax_identification VARCHAR(100) NOT NULL
);

COMMENT ON TABLE corporate_profiles IS 'Structural and registration details for corporate, SME, or institutional clients';


-- ====================================================================
-- 4. CUSTOMER ADDRESSES
-- ====================================================================
CREATE TABLE customer_addresses (
    address_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
    address_type address_type_enum NOT NULL,
    address_line_1 VARCHAR(255) NOT NULL,
    address_line_2 VARCHAR(255) NULL,
    city VARCHAR(100) NOT NULL,
    state_province VARCHAR(100) NULL,
    postal_code VARCHAR(20) NULL,
    country_code CHAR(3) NOT NULL, -- ISO 3166-1 alpha-3
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    effective_from DATE NOT NULL,
    effective_to DATE NULL,
    CONSTRAINT chk_address_dates CHECK (effective_to IS NULL OR effective_to >= effective_from)
);

COMMENT ON TABLE customer_addresses IS 'Normalized table supporting multiple addresses per customer with effective dating';


-- ====================================================================
-- 5. CUSTOMER CONTACTS
-- ====================================================================
CREATE TABLE customer_contacts (
    contact_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
    contact_type contact_type_enum NOT NULL,
    country_dial_code VARCHAR(5) NULL,
    contact_value VARCHAR(255) NOT NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    opt_in_marketing BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE customer_contacts IS 'Telecommunication and digital communication channels linked to a party';


-- ====================================================================
-- 6. CUSTOMER IDENTIFICATIONS (KYC Documents)
-- ====================================================================
CREATE TABLE customer_identifications (
    identification_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
    id_type id_type_enum NOT NULL,
    id_number VARCHAR(100) NOT NULL,
    issuing_country CHAR(3) NOT NULL, -- ISO 3166-1 alpha-3
    issuing_authority VARCHAR(150) NULL,
    issue_date DATE NULL,
    expiry_date DATE NULL,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_id_expiry CHECK (expiry_date IS NULL OR expiry_date >= issue_date)
);

COMMENT ON TABLE customer_identifications IS 'Government-issued identification documents used for identity verification';


-- ====================================================================
-- 7. CUSTOMER EMPLOYMENT
-- ====================================================================
CREATE TABLE customer_employment (
    employment_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL REFERENCES parties(party_id) ON DELETE CASCADE,
    employment_status employment_status_enum NOT NULL,
    employer_name VARCHAR(150) NULL,
    occupation VARCHAR(100) NULL,
    industry_sector VARCHAR(100) NULL,
    annual_income DECIMAL(18,2) NULL,
    income_currency CHAR(3) NOT NULL DEFAULT 'USD',
    source_of_wealth VARCHAR(100) NOT NULL
);

COMMENT ON TABLE customer_employment IS 'Occupational and source-of-wealth details for AML and credit scoring';


-- ====================================================================
-- 8. CUSTOMER KYC & COMPLIANCE
-- ====================================================================
CREATE TABLE customer_kyc (
    kyc_id BIGSERIAL PRIMARY KEY,
    party_id BIGINT NOT NULL UNIQUE REFERENCES parties(party_id) ON DELETE CASCADE,
    kyc_status kyc_status_enum NOT NULL DEFAULT 'PENDING',
    risk_rating risk_rating_enum NOT NULL DEFAULT 'LOW',
    is_pep BOOLEAN NOT NULL DEFAULT FALSE,
    pep_details TEXT NULL,
    sanctions_check_status VARCHAR(20) NOT NULL DEFAULT 'CLEAR',
    last_review_date TIMESTAMP WITH TIME ZONE NULL,
    next_review_date TIMESTAMP WITH TIME ZONE NULL
);

COMMENT ON TABLE customer_kyc IS 'Regulatory compliance, risk profiling, and anti-money laundering statuses';


-- ====================================================================
-- INDEXES FOR PERFORMANCE OPTIMIZATION
-- ====================================================================
CREATE INDEX idx_parties_status ON parties(customer_status);
CREATE INDEX idx_parties_segment ON parties(customer_segment);
CREATE INDEX idx_individual_names ON individual_profiles(last_name, first_name);
CREATE INDEX idx_corporate_name ON corporate_profiles(company_name);
CREATE INDEX idx_corporate_reg_no ON corporate_profiles(registration_number);
CREATE INDEX idx_addresses_party ON customer_addresses(party_id);
CREATE INDEX idx_contacts_party ON customer_contacts(party_id);
CREATE INDEX idx_identifications_number ON customer_identifications(id_number);
CREATE INDEX idx_kyc_risk ON customer_kyc(risk_rating);


-- ====================================================================
-- AUTOMATIC UPDATED_AT TRIGGER FUNCTION
-- ====================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER trg_parties_updated_at
    BEFORE UPDATE ON parties
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
