-- ============================================================
-- MODULE 1B — ÉTAPE 2 : FUTURE GRANTS + MFA + AUDIT PUBLIC
-- ============================================================
-- Les future grants garantissent que toute nouvelle table
-- hérite automatiquement des permissions. Sans ça, chaque
-- CREATE TABLE nécessite un nouveau GRANT — erreur #1.
--
-- On vérifie aussi les anti-patterns RBAC :
--   • Grants au rôle PUBLIC (= grant à tout le monde)
--   • Utilisateurs sans MFA
--   • Rôles orphelins
--
-- Pré-requis : 01_rbac_architecture.sql exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. FUTURE GRANTS — HÉRITAGE AUTOMATIQUE
-- ────────────────────────────────────────────────────────────

GRANT SELECT ON FUTURE TABLES IN DATABASE VOLTAIRE_RH TO ROLE AR_VOLTAIRE_RH_READ;
GRANT SELECT ON FUTURE TABLES IN DATABASE VOLTAIRE_CRM TO ROLE AR_VOLTAIRE_CRM_READ;
GRANT SELECT ON FUTURE TABLES IN DATABASE VOLTAIRE_FINANCE TO ROLE AR_VOLTAIRE_FINANCE_READ;
GRANT SELECT ON FUTURE TABLES IN DATABASE VOLTAIRE_DATALAKE TO ROLE AR_VOLTAIRE_DATALAKE_READ;

GRANT INSERT, UPDATE, DELETE ON FUTURE TABLES IN DATABASE VOLTAIRE_RH TO ROLE AR_VOLTAIRE_RH_WRITE;
GRANT INSERT, UPDATE, DELETE ON FUTURE TABLES IN DATABASE VOLTAIRE_CRM TO ROLE AR_VOLTAIRE_CRM_WRITE;
GRANT INSERT, UPDATE, DELETE ON FUTURE TABLES IN DATABASE VOLTAIRE_DATALAKE TO ROLE AR_VOLTAIRE_DATALAKE_WRITE;

GRANT USAGE ON FUTURE SCHEMAS IN DATABASE VOLTAIRE_RH TO ROLE AR_VOLTAIRE_RH_READ;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE VOLTAIRE_CRM TO ROLE AR_VOLTAIRE_CRM_READ;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE VOLTAIRE_FINANCE TO ROLE AR_VOLTAIRE_FINANCE_READ;
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE VOLTAIRE_DATALAKE TO ROLE AR_VOLTAIRE_DATALAKE_READ;

-- ────────────────────────────────────────────────────────────
-- B. AUDIT — GRANTS AU RÔLE PUBLIC (anti-pattern #1)
-- ────────────────────────────────────────────────────────────

SHOW GRANTS TO ROLE PUBLIC;

-- ────────────────────────────────────────────────────────────
-- C. AUDIT — UTILISATEURS SANS MFA
-- ────────────────────────────────────────────────────────────

SELECT NAME, LOGIN_NAME, HAS_MFA, DISABLED, DEFAULT_ROLE,
  LAST_SUCCESS_LOGIN
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS
WHERE DELETED_ON IS NULL
  AND DISABLED = 'false'
ORDER BY HAS_MFA, NAME;

-- ────────────────────────────────────────────────────────────
-- D. AUDIT — RÔLES AVEC TROP DE PRIVILÈGES
-- ────────────────────────────────────────────────────────────

SELECT GRANTEE_NAME AS ROLE_NAME,
  COUNT(*) AS NB_PRIVILEGES,
  COUNT(DISTINCT GRANTED_ON) AS NB_TYPES_OBJETS
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE DELETED_ON IS NULL
  AND GRANTED_ON != 'ROLE'
GROUP BY GRANTEE_NAME
ORDER BY NB_PRIVILEGES DESC
LIMIT 10;
