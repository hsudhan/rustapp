DO $$
DECLARE
    v_party_id BIGINT;
    v_type party_type_enum;
    v_segment customer_segment_enum;
    v_status customer_status_enum;
    v_first_names TEXT[] := ARRAY['James', 'Mary', 'John', 'Patricia', 'Robert', 'Jennifer', 'Michael', 'Linda', 'William', 'Elizabeth', 'David', 'Barbara', 'Richard', 'Susan', 'Joseph', 'Jessica', 'Thomas', 'Sarah', 'Charles', 'Karen'];
    v_last_names TEXT[] := ARRAY['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Miller', 'Davis', 'Garcia', 'Rodriguez', 'Wilson', 'Martinez', 'Anderson', 'Taylor', 'Thomas', 'Hernandez', 'Moore', 'Martin', 'Jackson', 'Thompson', 'White'];
    v_cities TEXT[] := ARRAY['New York', 'Los Angeles', 'Chicago', 'Houston', 'Phoenix', 'Philadelphia', 'San Antonio', 'San Diego', 'Dallas', 'San Jose'];
    v_streets TEXT[] := ARRAY['Main St', 'First Ave', 'Park Rd', 'Broadway', 'Oak St', 'Pine St', 'Cedar Ln', 'Elm St', 'Maple Ave', 'Washington Blvd'];
    v_companies TEXT[] := ARRAY['Global Tech', 'Apex Solutions', 'Venture Holdings', 'Pioneer Logistics', 'Summit Capital', 'Nexus Industries', 'Quantum Systems', 'Alpha Ventures', 'Blue Ocean Trade', 'Horizon Media'];
    i INT;
BEGIN
    FOR i IN 1..1000 LOOP
        -- Distribute 80% individual and 20% corporate profiles
        IF i <= 800 THEN
            v_type := 'IN';
            v_segment := (ARRAY['RETAIL', 'WEALTH', 'SME'])[1 + floor(random() * 3)]::customer_segment_enum;
        ELSE
            v_type := 'CORP';
            v_segment := (ARRAY['SME', 'CORPORATE', 'INSTITUTIONAL'])[1 + floor(random() * 3)]::customer_segment_enum;
        END IF;
        
        v_status := (ARRAY['ACTIVE', 'ACTIVE', 'ACTIVE', 'INACTIVE', 'DORMANT', 'PENDING'])[1 + floor(random() * 6)]::customer_status_enum;

        -- Insert into core parties table
        INSERT INTO parties (party_type, customer_segment, customer_status, home_branch_id, preferred_language)
        VALUES (v_type, v_segment, v_status, 'BR-' || lpad((1 + floor(random() * 50))::text, 3, '0'), 'en')
        RETURNING party_id INTO v_party_id;

        -- Insert into dependent profile tables based on party type
        IF v_type = 'IN' THEN
            INSERT INTO individual_profiles (
                party_id, title, first_name, last_name, date_of_birth, gender, nationality, citizenship_status
            ) VALUES (
                v_party_id,
                CASE WHEN random() > 0.5 THEN 'Mr' ELSE 'Ms' END,
                v_first_names[1 + floor(random() * array_length(v_first_names, 1))::int],
                v_last_names[1 + floor(random() * array_length(v_last_names, 1))::int],
                CURRENT_DATE - (18 + floor(random() * 50))::int * INTERVAL '1 year',
                CASE WHEN random() > 0.5 THEN 'Male' ELSE 'Female' END,
                'USA',
                'Citizen'
            );

            INSERT INTO customer_employment (
                party_id, employment_status, employer_name, occupation, annual_income, income_currency, source_of_wealth
            ) VALUES (
                v_party_id,
                'EMPLOYED',
                'Company ' || floor(random() * 1000),
                'Professional',
                40000 + floor(random() * 120000),
                'USD',
                'SALARY'
            );
        ELSE
            INSERT INTO corporate_profiles (
                party_id, company_name, registration_number, incorporation_date, country_of_inc, industry_code, business_structure, tax_identification
            ) VALUES (
                v_party_id,
                v_companies[1 + floor(random() * array_length(v_companies, 1))::int] || ' ' || i,
                'REG-' || lpad(i::text, 6, '0'),
                CURRENT_DATE - (1 + floor(random() * 15))::int * INTERVAL '1 year',
                'USA',
                '5415',
                'LLC',
                'EIN-' || lpad(i::text, 9, '0')
            );
        END IF;

        -- Insert address record
        INSERT INTO customer_addresses (
            party_id, address_type, address_line_1, city, state_province, postal_code, country_code, is_primary, effective_from
        ) VALUES (
            v_party_id,
            'RESIDENTIAL',
            (1 + floor(random() * 999))::text || ' ' || v_streets[1 + floor(random() * array_length(v_streets, 1))::int],
            v_cities[1 + floor(random() * array_length(v_cities, 1))::int],
            'NY',
            lpad((10000 + floor(random() * 89999))::text, 5, '0'),
            'USA',
            TRUE,
            CURRENT_DATE - INTERVAL '1 year'
        );

        -- Insert contact record
        INSERT INTO customer_contacts (
            party_id, contact_type, country_dial_code, contact_value, is_primary, is_verified
        ) VALUES (
            v_party_id,
            'MOBILE',
            '+1',
            '555-' || lpad((floor(random() * 900) + 100)::text, 3, '0') || '-' || lpad((floor(random() * 9000) + 1000)::text, 4, '0'),
            TRUE,
            TRUE
        );

        -- Insert identification document
        INSERT INTO customer_identifications (
            party_id, id_type, id_number, issuing_country, issue_date, expiry_date, is_primary
        ) VALUES (
            v_party_id,
            CASE WHEN v_type = 'IN' THEN 'PASSPORT'::id_type_enum ELSE 'TAX_ID'::id_type_enum END,
            'ID-' || lpad(i::text, 8, '0'),
            'USA',
            CURRENT_DATE - INTERVAL '2 year',
            CURRENT_DATE + INTERVAL '8 year',
            TRUE
        );

        -- Insert compliance / KYC record
        INSERT INTO customer_kyc (
            party_id, kyc_status, risk_rating, is_pep, sanctions_check_status
        ) VALUES (
            v_party_id,
            'APPROVED',
            CASE WHEN random() < 0.85 THEN 'LOW'::risk_rating_enum ELSE 'MEDIUM'::risk_rating_enum END,
            FALSE,
            'CLEAR'
        );
    END LOOP;
END $$;