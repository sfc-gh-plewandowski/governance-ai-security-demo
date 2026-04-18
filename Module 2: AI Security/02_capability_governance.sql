-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- 5 leviers de contrôle AI :
--   1. Cross-Region       — où l'inférence s'exécute (mTLS)
--   2. Model Allowlist    — quels modèles existent dans le compte
--   3. Model RBAC         — quel rôle peut utiliser quel modèle
--   4. Feature Access     — quel rôle peut utiliser quelle feature Cortex
--   5. Budget Limits      — combien chaque utilisateur peut consommer
--
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- 0. INVENTAIRE — ÉTAT DES LIEUX
-- ════════════════════════════════════════════════════════════

CALL SNOWFLAKE.MODELS.CORTEX_BASE_MODELS_REFRESH();

SHOW MODELS IN SNOWFLAKE.MODELS;

SELECT CURRENT_REGION() AS REGION_ACTUELLE;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français, en une seule phrase.'
) AS TEST_MODELE_DISPONIBLE;


-- ════════════════════════════════════════════════════════════
-- 1. CROSS-REGION — OÙ L'INFÉRENCE S'EXÉCUTE
-- ════════════════════════════════════════════════════════════
-- Doc : https://docs.snowflake.com/en/sql-reference/parameters#label-cortex-enable-cross-region

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- Restreindre à AWS Europe (mTLS entre régions AWS EU uniquement)
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

-- ✅ Mistral/Llama hébergés sur AWS → OK
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Où sommes-nous hébergés ?'
) AS MODELE_AWS_OK;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour.'
) AS MODELE_AWS_OK_2;

-- ❌ Modèles hébergés sur Azure (ex: OpenAI GPT) → bloqués par AWS_EU
-- Note: si le modèle n'est pas déployé dans cette région du tout,
-- l'erreur sera "Model unavailable" plutôt que "Cross-region blocked".

-- Valeurs possibles :
--   DISABLED     → inférence dans la région du compte uniquement
--   AWS_EU       → AWS Europe (eu-central-1, eu-west-1, eu-north-1…)
--   AZURE_EU     → Azure Europe (westeurope, francecentral…)
--   AWS_US       → AWS US regions
--   ANY_REGION   → aucune restriction géographique
--   (voir doc pour la liste complète)

-- restaurer
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';


-- ════════════════════════════════════════════════════════════
-- 2. MODEL ALLOWLIST — QUELS MODÈLES SONT DISPONIBLES
-- ════════════════════════════════════════════════════════════
-- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#label-cortex-llm-allowlist

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

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
-- 3. MODEL RBAC — QUEL RÔLE UTILISE QUEL MODÈLE
-- ════════════════════════════════════════════════════════════
-- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#label-cortex-llm-rbac
-- Chaque modèle a un rôle applicatif : SNOWFLAKE."CORTEX-MODEL-ROLE-<MODELE>"

-- 3a. Lister les rôles applicatifs modèle
SHOW APPLICATION ROLES LIKE '%CORTEX-MODEL%' IN APPLICATION SNOWFLAKE;

-- 3b. Qui a le super-rôle modèles ?
SHOW GRANTS OF APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN;

-- 3c. SETUP : ALLOWLIST = None + grants par rôle

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'None';

-- DATA_ANALYST → mistral-large2 + fonctions managées
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-SENTIMENT"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-7B"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ANALYST;

-- DATA_ENGINEER → mistral-large2 + llama3.1-70b + deepseek-r1
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-DEEPSEEK-R1"
  TO ROLE DATA_ENGINEER;

-- SECURITY_ADMIN → tous les modèles + gestion
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ALL"
  TO ROLE SECURITY_ADMIN;
GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN
  TO ROLE SECURITY_ADMIN;

-- 3d. TEST par rôle

USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ mistral-large2 autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Résume en une phrase : le RBAC protège les modèles AI.'
) AS ANALYST_MISTRAL_OK;

-- ❌ deepseek-r1 pas autorisé pour DATA_ANALYST
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Résume en une phrase : le RBAC protège les modèles AI.'
) AS ANALYST_DEEPSEEK_BLOQUE;

-- ✅ AI_TRANSLATE (arctic-translate autorisé)
SELECT SNOWFLAKE.CORTEX.TRANSLATE(
  'Data governance is essential for AI security.', 'en', 'fr'
) AS ANALYST_TRANSLATE_OK;

-- ✅ SUMMARIZE (mistral-7b autorisé)
SELECT SNOWFLAKE.CORTEX.SUMMARIZE(
  'La gouvernance des données est essentielle pour la sécurité AI.
   Elle comprend le contrôle d''accès, la classification et le monitoring.'
) AS ANALYST_SUMMARIZE_OK;


USE ROLE DATA_ENGINEER;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ deepseek-r1 autorisé pour DATA_ENGINEER
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Explique le concept de least privilege en une phrase.'
) AS ENGINEER_DEEPSEEK_OK;

-- ✅ llama3.1-70b autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour.'
) AS ENGINEER_LLAMA_OK;


USE ROLE SECURITY_ADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ accès total via CORTEX-MODEL-ROLE-ALL
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Bonjour depuis SECURITY_ADMIN.'
) AS SECADMIN_MISTRAL_OK;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Bonjour depuis SECURITY_ADMIN.'
) AS SECADMIN_DEEPSEEK_OK;


-- 3e. NETTOYAGE
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';

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
-- 4. FEATURE ACCESS — QUEL RÔLE UTILISE QUELLE FEATURE CORTEX
-- ════════════════════════════════════════════════════════════
-- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#cortex-llm-privileges
-- 5 database roles contrôlent l'accès aux features Cortex :
--   CORTEX_USER         → accès complet (AI functions + agents + search…)
--   AI_FUNCTIONS_USER   → AI functions scalaires uniquement (pas agents/search)
--   CORTEX_AGENT_USER   → Cortex Agents API uniquement
--   CORTEX_EMBED_USER   → fonctions d'embedding uniquement
--   COPILOT_USER        → Cortex Code dans Snowsight

-- 4a. État actuel : qui a quoi ?
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_EMBED_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.COPILOT_USER;

-- Par défaut :
--   CORTEX_USER  → PUBLIC (tout le monde)
--   COPILOT_USER → PUBLIC (tout le monde)
--   Les autres   → ACCOUNTADMIN uniquement

-- 4b. DEMO : restreindre l'accès Cortex

-- Retirer l'accès Cortex global
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC;

-- DATA_ANALYST → AI functions scalaires uniquement (pas agents, pas search)
GRANT DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER TO ROLE DATA_ANALYST;

-- DATA_ENGINEER → AI functions + agents
GRANT DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER TO ROLE DATA_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE DATA_ENGINEER;

-- SECURITY_ADMIN → accès complet
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SECURITY_ADMIN;

-- 4c. TEST

USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ AI_COMPLETE fonctionne (AI_FUNCTIONS_USER)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Dis bonjour.'
) AS ANALYST_AI_FUNCTION_OK;

USE ROLE DATA_ENGINEER;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ AI_COMPLETE fonctionne (AI_FUNCTIONS_USER)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Dis bonjour.'
) AS ENGINEER_AI_FUNCTION_OK;


-- 4d. NETTOYAGE
USE ROLE ACCOUNTADMIN;

REVOKE DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER FROM ROLE DATA_ANALYST;
REVOKE DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER FROM ROLE DATA_ENGINEER;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER FROM ROLE DATA_ENGINEER;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE SECURITY_ADMIN;

-- Restaurer l'accès global
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE PUBLIC;


-- ════════════════════════════════════════════════════════════
-- 5. BUDGET LIMITS — LIMITES DE CONSOMMATION
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Limiter la consommation Cortex Code par utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;


-- ════════════════════════════════════════════════════════════
-- 6. AUDIT — QUI A UTILISÉ QUELS MODÈLES ?
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
-- RÉCAP : 5 LEVIERS DE GOUVERNANCE AI
-- ════════════════════════════════════════════════════════════
-- ┌──────────────────────┬───────────────────────────┬──────────────┐
-- │ Levier               │ Contrôle                  │ Granularité  │
-- ├──────────────────────┼───────────────────────────┼──────────────┤
-- │ 1. CROSS_REGION      │ Où tourne l'inférence     │ Compte       │
-- │ 2. MODELS_ALLOWLIST  │ Quels modèles existent    │ Compte       │
-- │ 3. MODEL RBAC        │ Qui utilise quel modèle   │ Rôle×Modèle  │
-- │ 4. FEATURE ACCESS    │ Qui utilise quelle feature│ Rôle×Feature │
-- │ 5. BUDGET LIMITS     │ Combien on consomme       │ Utilisateur  │
-- └──────────────────────┴───────────────────────────┴──────────────┘
