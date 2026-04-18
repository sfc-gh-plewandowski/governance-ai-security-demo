-- ============================================================
-- MODULE 2E — MONITORING ET AUDIT AI
-- ============================================================
-- La gouvernance inclut l'auditabilité.
-- On surveille : qui appelle quel modèle, combien de fois,
-- à quel coût. On détecte les anomalies.
--
-- Boucle complète : classify → protect → use → MONITOR → refine
--
-- Pré-requis : Modules 2A–2C exécutés (avoir fait des appels Cortex)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. CONSOMMATION CORTEX — VUE GLOBALE
-- ────────────────────────────────────────────────────────────

SELECT SERVICE_TYPE, USAGE_DATE,
  CREDITS_USED, CREDITS_USED_COMPUTE
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE ILIKE '%CORTEX%'
  AND USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
ORDER BY USAGE_DATE DESC;

-- Note : peut être vide si pas encore de données de facturation Cortex.
-- La latence ACCOUNT_USAGE est ~2h.

-- ────────────────────────────────────────────────────────────
-- B. DÉTAIL PAR FONCTION CORTEX
-- ────────────────────────────────────────────────────────────

SELECT
  FUNCTION_NAME,
  MODEL_NAME,
  COUNT(*) AS NB_APPELS,
  SUM(TOKENS) AS TOKENS_TOTAL,
  SUM(TOKEN_CREDITS) AS CREDITS_TOKENS,
  MIN(START_TIME) AS PREMIER_APPEL,
  MAX(START_TIME) AS DERNIER_APPEL
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY TOKENS_TOTAL DESC;

-- ────────────────────────────────────────────────────────────
-- C. QUERY HISTORY — QUI A APPELÉ CORTEX AUJOURD'HUI ?
-- ────────────────────────────────────────────────────────────

SELECT
  USER_NAME,
  ROLE_NAME,
  LEFT(QUERY_TEXT, 120) AS REQUETE,
  START_TIME,
  TOTAL_ELAPSED_TIME/1000 AS DUREE_SEC,
  CREDITS_USED_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT ILIKE '%CORTEX%COMPLETE%'
  AND START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 20;

-- ────────────────────────────────────────────────────────────
-- D. DÉTECTION D'ANOMALIES — UTILISATION EXCESSIVE
-- ────────────────────────────────────────────────────────────

SELECT
  USER_NAME,
  DATE_TRUNC('hour', START_TIME) AS HEURE,
  COUNT(*) AS NB_REQUETES_CORTEX
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT ILIKE '%CORTEX%COMPLETE%'
  AND START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
GROUP BY USER_NAME, DATE_TRUNC('hour', START_TIME)
ORDER BY NB_REQUETES_CORTEX DESC;

-- En production : mettre un seuil d'alerte si NB > 50/heure

-- ────────────────────────────────────────────────────────────
-- E. LIMITES BUDGÉTAIRES — CREDIT LIMITS PAR UTILISATEUR
-- ────────────────────────────────────────────────────────────

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Pour limiter un utilisateur à N crédits/jour :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
