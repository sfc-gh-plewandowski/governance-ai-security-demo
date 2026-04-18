-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- 3 leviers : ALLOWLIST · MODEL RBAC · CROSS-REGION
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- A. INVENTAIRE — QUELS MODÈLES SONT DISPONIBLES
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

CALL SNOWFLAKE.MODELS.CORTEX_BASE_MODELS_REFRESH();

SHOW MODELS IN SNOWFLAKE.MODELS;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français, en une seule phrase.'
) AS TEST_MODELE_DISPONIBLE;


-- ════════════════════════════════════════════════════════════
-- B. ALLOWLIST — RESTREINDRE LES MODÈLES AU NIVEAU COMPTE
-- ════════════════════════════════════════════════════════════

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2';

-- ✅ autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Dis bonjour.'
) AS MODELE_AUTORISE;

-- ❌ bloqué → "Unknown model"
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour.'
) AS MODELE_BLOQUE;

-- restaurer
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';


-- ════════════════════════════════════════════════════════════
-- C. MODEL RBAC — CONTRÔLE PAR RÔLE, PAR MODÈLE
-- ════════════════════════════════════════════════════════════
-- Après le refresh (section A), chaque modèle a un rôle applicatif :
-- SNOWFLAKE."CORTEX-MODEL-ROLE-<MODELE>"

-- C1. Lister les rôles applicatifs modèle
SHOW APPLICATION ROLES LIKE '%CORTEX-MODEL%' IN APPLICATION SNOWFLAKE;

-- C2. Vérifier qui a CORTEX_MODELS_ADMIN (le super-rôle modèles)
SHOW GRANTS OF APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN;

-- C3. Best practice : ALLOWLIST = None + grants par rôle

-- Étape 1 : couper l'accès global
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'None';

-- Étape 2 : DATA_ANALYST → peut utiliser mistral-large2 uniquement
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ANALYST;

-- Étape 3 : DATA_ENGINEER → mistral-large2 + llama3.1-70b + deepseek-r1
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-DEEPSEEK-R1"
  TO ROLE DATA_ENGINEER;

-- Étape 4 : SECURITY_ADMIN → gestion complète (tous les modèles)
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ALL"
  TO ROLE SECURITY_ADMIN;
GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN
  TO ROLE SECURITY_ADMIN;

-- Étape 5 : fonctions managées (AI_TRANSLATE, SUMMARIZE, AI_REDACT…)
-- Ces fonctions utilisent des modèles internes. Il faut les autoriser aussi.
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-SENTIMENT"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-7B"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ANALYST;


-- ════════════════════════════════════════════════════════════
-- D. TEST RBAC — VÉRIFICATION PAR RÔLE
-- ════════════════════════════════════════════════════════════

-- D1. DATA_ANALYST : mistral-large2 → ✅
USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Résume en une phrase : le RBAC protège les modèles AI.'
) AS ANALYST_MISTRAL_OK;

-- D2. DATA_ANALYST : deepseek-r1 → ❌ pas autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Résume en une phrase : le RBAC protège les modèles AI.'
) AS ANALYST_DEEPSEEK_BLOQUE;

-- D3. DATA_ANALYST : AI_TRANSLATE (arctic-translate) → ✅
SELECT SNOWFLAKE.CORTEX.TRANSLATE(
  'Data governance is essential for AI security.',
  'en', 'fr'
) AS ANALYST_TRANSLATE_OK;

-- D4. DATA_ANALYST : SUMMARIZE (mistral-7b) → ✅
SELECT SNOWFLAKE.CORTEX.SUMMARIZE(
  'La gouvernance des données est essentielle pour la sécurité AI.
   Elle comprend le contrôle d''accès, la classification et le monitoring.'
) AS ANALYST_SUMMARIZE_OK;


-- D5. DATA_ENGINEER : deepseek-r1 → ✅
USE ROLE DATA_ENGINEER;
USE WAREHOUSE WORKSHOP_WH;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Explique le concept de least privilege en une phrase.'
) AS ENGINEER_DEEPSEEK_OK;

-- D6. DATA_ENGINEER : llama3.1-70b → ✅
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour.'
) AS ENGINEER_LLAMA_OK;


-- D7. SECURITY_ADMIN : accès total via CORTEX-MODEL-ROLE-ALL
USE ROLE SECURITY_ADMIN;
USE WAREHOUSE WORKSHOP_WH;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Bonjour depuis SECURITY_ADMIN.'
) AS SECADMIN_MISTRAL_OK;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Bonjour depuis SECURITY_ADMIN.'
) AS SECADMIN_DEEPSEEK_OK;


-- ════════════════════════════════════════════════════════════
-- E. NETTOYAGE RBAC — RESTAURER ALLOWLIST = ALL
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';

-- Révoquer les grants de démonstration
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-SENTIMENT"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-7B"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  FROM ROLE DATA_ANALYST;

REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  FROM ROLE DATA_ENGINEER;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  FROM ROLE DATA_ENGINEER;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-DEEPSEEK-R1"
  FROM ROLE DATA_ENGINEER;

REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ALL"
  FROM ROLE SECURITY_ADMIN;
REVOKE APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN
  FROM ROLE SECURITY_ADMIN;


-- ════════════════════════════════════════════════════════════
-- F. CROSS-REGION — CONTRÔLE GÉOGRAPHIQUE DE L'INFÉRENCE
-- ════════════════════════════════════════════════════════════

SELECT CURRENT_REGION() AS REGION_ACTUELLE;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- Restreindre à AWS Europe
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

-- ✅ Mistral/Llama hébergés sur AWS → OK
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Où sommes-nous hébergés ?'
) AS MODELE_AWS_OK;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour.'
) AS MODELE_AWS_OK_2;

-- ❌ Modèles hébergés sur Azure → bloqués par AWS_EU
-- OpenAI (GPT) est hébergé sur Azure. Avec AWS_EU, il est hors périmètre.
-- Note: si le modèle n'est pas déployé dans la région, l'erreur sera
-- "Model unavailable" plutôt que "Cross-region blocked".

-- restaurer
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';


-- ════════════════════════════════════════════════════════════
-- G. LIMITES BUDGÉTAIRES CORTEX
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Limiter la consommation par utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;

-- ════════════════════════════════════════════════════════════
-- H. AUDIT — QUI A UTILISÉ QUELS MODÈLES ?
-- ════════════════════════════════════════════════════════════

SELECT
    h.USAGE_TIME,
    u.NAME AS USER_NAME,
    h.FUNCTION_NAME,
    h.MODEL_NAME,
    h.TOKENS,
    h.TOKEN_CREDITS,
    h.QUERY_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY h.USAGE_TIME DESC
LIMIT 20;

-- ════════════════════════════════════════════════════════════
-- RÉCAP : 3 LEVIERS DE GOUVERNANCE AI
-- ════════════════════════════════════════════════════════════
-- ┌─────────────────────┬────────────────────┬──────────────┐
-- │ Levier              │ Contrôle           │ Granularité  │
-- ├─────────────────────┼────────────────────┼──────────────┤
-- │ MODELS_ALLOWLIST    │ Quels modèles      │ Compte       │
-- │ MODEL RBAC (roles)  │ Qui utilise quoi   │ Rôle×Modèle  │
-- │ CROSS_REGION        │ Où tourne l'infér. │ Compte       │
-- └─────────────────────┴────────────────────┴──────────────┘
