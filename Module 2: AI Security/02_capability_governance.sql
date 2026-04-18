-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- Dimension 2 : qui peut utiliser quel modèle, quel agent,
-- quels outils. On ne contrôle pas juste les DONNÉES (Dim 1),
-- on contrôle aussi les CAPACITÉS AI elles-mêmes.
--
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. MODEL ALLOWLIST — QUELS MODÈLES SONT DISPONIBLES
-- ────────────────────────────────────────────────────────────

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

-- ────────────────────────────────────────────────────────────
-- B. TESTER LA RESTRICTION (DÉMONSTRATION)
-- ────────────────────────────────────────────────────────────

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2';

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français.'
) AS MODELE_AUTORISE;

-- Ce modèle devrait échouer car non dans l'allowlist :
-- SELECT SNOWFLAKE.CORTEX.COMPLETE(
--   'llama3.1-70b',
--   'Dis bonjour en français.'
-- ) AS MODELE_BLOQUE;

-- Remettre ALL pour la suite du workshop
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';

-- ────────────────────────────────────────────────────────────
-- C. MODEL RBAC — CONTRÔLE PAR RÔLE (APPLICATION ROLES)
-- ────────────────────────────────────────────────────────────

SHOW APPLICATION ROLES IN APPLICATION SNOWFLAKE;

-- Exemple : donner accès à un modèle spécifique par rôle
-- GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN TO ROLE SECURITY_ADMIN;

-- ────────────────────────────────────────────────────────────
-- D. CORTEX_ENABLED_CROSS_REGION — CONTRÔLE GÉOGRAPHIQUE
-- ────────────────────────────────────────────────────────────

SELECT CURRENT_REGION() AS REGION_ACTUELLE;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- Valeurs possibles :
-- DISABLED       → inférence dans la région du compte uniquement
-- AWS_EU         → AWS Europe seulement (recommandé pour RGPD)
-- AWS_US_EU      → AWS US + EU (attention RGPD !)

-- ────────────────────────────────────────────────────────────
-- E. LIMITES BUDGÉTAIRES CORTEX
-- ────────────────────────────────────────────────────────────

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Pour limiter l'utilisation AI par utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
