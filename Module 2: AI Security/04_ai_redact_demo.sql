-- ============================================================
-- MODULE 3D: AI_REDACT — PII Detection & Redaction
-- End-to-End Demo
-- ============================================================
-- Prerequisites: Modules 1A–1D executed (SECURITY_WORKSHOP database,
--                WORKSHOP_WH warehouse, roles created)
-- Time estimate: 25 minutes
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;
USE DATABASE SECURITY_WORKSHOP;
USE SCHEMA PUBLIC;

-- ============================================================
-- STEP 1: INGEST — Create PII-rich unstructured text data
-- ============================================================
-- Scenario: customer support transcripts from a call center.
-- These contain PII scattered in free-text — exactly the kind
-- of data where column-level masking can't help because PII
-- is embedded in unstructured fields.

CREATE OR REPLACE TABLE SUPPORT_TRANSCRIPTS (
    TICKET_ID NUMBER AUTOINCREMENT,
    AGENT_NAME STRING,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TRANSCRIPT STRING
);

INSERT INTO SUPPORT_TRANSCRIPTS (AGENT_NAME, TRANSCRIPT)
VALUES
('Agent_01',
 'Customer John Smith called about his account. His email is john.smith@gmail.com and his phone number is (415) 555-0198. He lives at 742 Evergreen Terrace, Springfield, IL 62704. His SSN is 123-45-6789. He reported unauthorized charges on his Visa ending in 4242.'),

('Agent_02',
 'Spoke with Marie Dupont regarding a billing dispute. She can be reached at marie.dupont@outlook.fr or +33 6 12 34 56 78. Date of birth: March 15, 1988. Her passport number is FR1234567. She mentioned her husband Pierre, who is 42 years old.'),

('Agent_03',
 'Call from David Chen, IP address 192.168.1.42. He needs to update his driver''s license on file: CA-D1234567. His tax ID is 987-65-4321. Payment card: 5500 0000 0000 0004, exp 12/27, CVV 123. Resides at 1600 Pennsylvania Avenue NW, Washington DC 20500.'),

('Agent_04',
 'Escalation from Eve Martinez, DPO at Acme Corp. She reported that employee records for Bob Wilson (SSN 234-56-7890, born 1990-07-22) and Carol Davis (email carol.davis@acme.com, salary $150,000) were accidentally shared externally. Contact Eve at eve.martinez@acme.com or +44 20 7946 0958.'),

('Agent_05',
 'Technical support ticket from Frank Lee. He is a male, age 33, located in Sydney. His IP is 10.0.1.15. He uses credit card 3530 1113 3330 0000. His company address is 200 George St, Sydney NSW 2000, Australia. Email: frank.lee@company.com.au.');

-- ============================================================
-- STEP 2: READ — View raw data with PII exposed
-- ============================================================

SELECT TICKET_ID, AGENT_NAME, TRANSCRIPT
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

-- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
-- DISCUSSION: Look at the raw transcripts. Names, emails,
-- SSNs, phone numbers, addresses, card numbers — all visible.
-- Column-level masking can't help here because PII is embedded
-- inside a free-text STRING column.
-- This is the gap AI_REDACT fills.
-- ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

-- ============================================================
-- STEP 3: REDACT — Apply AI_REDACT (default mode)
-- ============================================================
-- AI_REDACT replaces PII with category placeholders like
-- [NAME], [EMAIL], [ADDRESS], [NATIONAL_ID], etc.

SELECT
    TICKET_ID,
    TRANSCRIPT AS original,
    AI_REDACT(TRANSCRIPT) AS redacted
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

-- ============================================================
-- STEP 4: SIDE-BY-SIDE — Visual comparison
-- ============================================================
-- Show original length vs redacted length to demonstrate
-- the transformation, plus a clean comparison view.

SELECT
    TICKET_ID,
    AGENT_NAME,
    LENGTH(TRANSCRIPT) AS original_chars,
    LENGTH(AI_REDACT(TRANSCRIPT)) AS redacted_chars,
    TRANSCRIPT AS with_pii,
    AI_REDACT(TRANSCRIPT) AS without_pii
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

-- ============================================================
-- STEP 5: DETECT — Find PII without redacting
-- ============================================================
-- detect mode returns a JSON object with span metadata:
-- category, start/end offsets, and matched text.
-- Use this for audit, reporting, or selective redaction.

SELECT
    TICKET_ID,
    AI_REDACT(
        input => TRANSCRIPT,
        return_error_details => FALSE,
        mode => 'detect'
    ) AS pii_spans
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

-- Flatten the spans to get one row per PII instance
SELECT
    t.TICKET_ID,
    s.value:category::STRING AS pii_category,
    s.value:text::STRING AS pii_value,
    s.value:start::NUMBER AS start_pos,
    s.value:end::NUMBER AS end_pos
FROM SUPPORT_TRANSCRIPTS t,
    LATERAL FLATTEN(
        input => AI_REDACT(
            input => t.TRANSCRIPT,
            return_error_details => FALSE,
            mode => 'detect'
        ):spans
    ) s
ORDER BY t.TICKET_ID, start_pos;

-- PII category summary across all transcripts
SELECT
    s.value:category::STRING AS pii_category,
    COUNT(*) AS occurrences
FROM SUPPORT_TRANSCRIPTS t,
    LATERAL FLATTEN(
        input => AI_REDACT(
            input => t.TRANSCRIPT,
            return_error_details => FALSE,
            mode => 'detect'
        ):spans
    ) s
GROUP BY pii_category
ORDER BY occurrences DESC;

-- ============================================================
-- STEP 6: SELECTIVE REDACTION — Target specific categories
-- ============================================================
-- Only redact names and emails — leave everything else visible.
-- Use case: analytics team needs addresses for geo analysis
-- but must not see personal identifiers.

SELECT
    TICKET_ID,
    AI_REDACT(
        input => TRANSCRIPT,
        categories => ['NAME', 'EMAIL']
    ) AS names_emails_only,
    AI_REDACT(
        input => TRANSCRIPT,
        categories => ['NATIONAL_ID', 'PAYMENT_CARD_DATA', 'DRIVERS_LICENSE']
    ) AS financial_ids_only,
    AI_REDACT(TRANSCRIPT) AS full_redaction
FROM SUPPORT_TRANSCRIPTS
WHERE TICKET_ID = 3;

-- ============================================================
-- STEP 7: ERROR HANDLING — Graceful failure for batch jobs
-- ============================================================

ALTER SESSION SET AI_SQL_ERROR_HANDLING_USE_FAIL_ON_ERROR = FALSE;

SELECT
    TICKET_ID,
    AI_REDACT(TRANSCRIPT, TRUE) AS result,
    result:value::STRING AS redacted_text,
    result:error::STRING AS error_message
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

ALTER SESSION SET AI_SQL_ERROR_HANDLING_USE_FAIL_ON_ERROR = TRUE;

-- ============================================================
-- STEP 8: PIPELINE — Redact then Analyze (AI_REDACT → AI_SENTIMENT)
-- ============================================================
-- Real-world pattern: redact PII first, then run analytics
-- on the safe text. This is how you build compliant AI pipelines.

CREATE OR REPLACE TABLE REDACTED_TRANSCRIPTS AS
SELECT
    TICKET_ID,
    AGENT_NAME,
    CREATED_AT,
    AI_REDACT(TRANSCRIPT) AS REDACTED_TRANSCRIPT
FROM SUPPORT_TRANSCRIPTS;

SELECT
    TICKET_ID,
    AGENT_NAME,
    REDACTED_TRANSCRIPT,
    SNOWFLAKE.CORTEX.SENTIMENT(REDACTED_TRANSCRIPT) AS sentiment_score
FROM REDACTED_TRANSCRIPTS
ORDER BY sentiment_score ASC;

-- ============================================================
-- STEP 9: GOVERNANCE INTEGRATION — Masking policy using AI_REDACT
-- ============================================================
-- The ultimate pattern: use AI_REDACT *inside* a masking policy.
-- Privileged roles see raw text; everyone else sees redacted text.
-- Governance is automatic — no manual redaction pipeline needed.

CREATE OR REPLACE MASKING POLICY MASK_TRANSCRIPT_PII
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        WHEN IS_ROLE_IN_SESSION('DATA_ENGINEER') THEN val
        ELSE AI_REDACT(val)
    END;

ALTER TABLE SUPPORT_TRANSCRIPTS
    MODIFY COLUMN TRANSCRIPT
    SET MASKING POLICY MASK_TRANSCRIPT_PII;

-- Now test with different roles:
USE ROLE SECURITY_ADMIN;
SELECT TICKET_ID, TRANSCRIPT FROM SECURITY_WORKSHOP.PUBLIC.SUPPORT_TRANSCRIPTS WHERE TICKET_ID = 1;
-- ^^^ Full PII visible

USE ROLE DATA_ANALYST;
SELECT TICKET_ID, TRANSCRIPT FROM SECURITY_WORKSHOP.PUBLIC.SUPPORT_TRANSCRIPTS WHERE TICKET_ID = 1;
-- ^^^ PII automatically redacted by the masking policy!

-- ============================================================
-- STEP 10: THE FULL PICTURE — Before and After summary
-- ============================================================

USE ROLE ACCOUNTADMIN;

ALTER TABLE SUPPORT_TRANSCRIPTS
    MODIFY COLUMN TRANSCRIPT
    UNSET MASKING POLICY;

SELECT '--- WITHOUT AI_REDACT ---' AS label;
SELECT TICKET_ID, LEFT(TRANSCRIPT, 120) || '...' AS preview
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

SELECT '--- WITH AI_REDACT ---' AS label;
SELECT TICKET_ID, LEFT(AI_REDACT(TRANSCRIPT), 120) || '...' AS preview
FROM SUPPORT_TRANSCRIPTS
ORDER BY TICKET_ID;

SELECT '--- DETECT MODE (PII inventory) ---' AS label;
SELECT
    s.value:category::STRING AS category,
    COUNT(*) AS total_found
FROM SUPPORT_TRANSCRIPTS t,
    LATERAL FLATTEN(
        input => AI_REDACT(
            input => t.TRANSCRIPT,
            return_error_details => FALSE,
            mode => 'detect'
        ):spans
    ) s
GROUP BY category
ORDER BY total_found DESC;

-- ============================================================
-- CLEANUP (optional)
-- ============================================================
-- DROP TABLE SUPPORT_TRANSCRIPTS;
-- DROP TABLE REDACTED_TRANSCRIPTS;
-- DROP MASKING POLICY MASK_TRANSCRIPT_PII;
