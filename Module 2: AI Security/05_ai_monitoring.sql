-- ============================================================
-- MODULE 2E — MONITORING & AUDIT AI — FERMER LA BOUCLE
-- ============================================================
-- « Gouverner sans surveiller, c'est construire une porte
--   sans vérifier si quelqu'un l'utilise. Le monitoring ferme
--   la boucle : classify → protect → use → MONITOR → refine. »
--
-- 4 actes :
--   1. Qui a appelé quels modèles ? (audit détaillé)
--   2. Combien ça coûte ? (consommation par fonction/modèle)
--   3. Comportement anormal ? (détection d'anomalies)
--   4. Limites budgétaires (contrôle de la dépense par user)
--
-- Durée : 15 min
-- Pré-requis : Modules 2A–2D exécutés (avoir fait des appels Cortex)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;


-- ════════════════════════════════════════════════════════════
-- ACTE 1 : QUI A APPELÉ QUELS MODÈLES ? — AUDIT DÉTAILLÉ
-- ════════════════════════════════════════════════════════════

-- 1a. Vue principale : CORTEX_AISQL_USAGE_HISTORY
-- Chaque appel Cortex AI SQL est tracé avec user, modèle,
-- fonction, tokens consommés, et query_id pour le drill-down.
SELECT
    h.USAGE_TIME,
    u.NAME AS UTILISATEUR,
    h.FUNCTION_NAME AS FONCTION,
    h.MODEL_NAME AS MODELE,
    h.TOKENS,
    h.TOKEN_CREDITS AS CREDITS,
    h.QUERY_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY h.USAGE_TIME DESC
LIMIT 20;

-- 1b. Vue enrichie avec rôle : CORTEX_AI_FUNCTIONS_USAGE_HISTORY
-- Cette vue contient ROLE_NAMES — essentiel pour l'audit.
SELECT
    START_TIME,
    FUNCTION_NAME AS FONCTION,
    MODEL_NAME AS MODELE,
    ROLE_NAMES AS ROLES_UTILISES,
    CREDITS,
    QUERY_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 20;

-- 1c. Temps réel via QUERY_HISTORY (latence ~0 vs ~2h pour ACCOUNT_USAGE)
-- En démo live, QUERY_HISTORY montre les appels faits il y a 5 min.
SELECT
    USER_NAME,
    ROLE_NAME,
    LEFT(QUERY_TEXT, 100) AS REQUETE,
    START_TIME,
    TOTAL_ELAPSED_TIME/1000 AS DUREE_SEC,
    CREDITS_USED_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT ILIKE '%CORTEX%COMPLETE%'
  AND START_TIME >= DATEADD(hour, -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 20;


-- ════════════════════════════════════════════════════════════
-- ACTE 2 : COMBIEN ÇA COÛTE ? — CONSOMMATION PAR MODÈLE
-- ════════════════════════════════════════════════════════════

-- 2a. Consommation par fonction + modèle (dernière semaine)
SELECT
    FUNCTION_NAME AS FONCTION,
    MODEL_NAME AS MODELE,
    COUNT(*) AS NB_APPELS,
    SUM(TOKENS) AS TOKENS_TOTAL,
    SUM(TOKEN_CREDITS) AS CREDITS_TOTAL
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY FUNCTION_NAME, MODEL_NAME
ORDER BY CREDITS_TOTAL DESC;

-- 2b. Consommation globale Cortex (vue de facturation)
SELECT
    SERVICE_TYPE,
    USAGE_DATE,
    CREDITS_USED,
    CREDITS_USED_COMPUTE
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE SERVICE_TYPE ILIKE '%CORTEX%'
  AND USAGE_DATE >= DATEADD(day, -30, CURRENT_DATE())
ORDER BY USAGE_DATE DESC;

-- 2c. Top utilisateurs par consommation AI
SELECT
    u.NAME AS UTILISATEUR,
    COUNT(*) AS NB_APPELS,
    SUM(h.TOKENS) AS TOKENS_TOTAL,
    SUM(h.TOKEN_CREDITS) AS CREDITS_TOTAL
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY h
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON h.USER_ID = u.USER_ID
WHERE h.USAGE_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY u.NAME
ORDER BY CREDITS_TOTAL DESC;


-- ════════════════════════════════════════════════════════════
-- ACTE 3 : DÉTECTION D'ANOMALIES
-- ════════════════════════════════════════════════════════════

-- 3a. Appels par heure par utilisateur (spike detection)
SELECT
    USER_NAME,
    DATE_TRUNC('hour', START_TIME) AS HEURE,
    COUNT(*) AS NB_APPELS_CORTEX
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT ILIKE '%CORTEX%COMPLETE%'
  AND START_TIME >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY USER_NAME, DATE_TRUNC('hour', START_TIME)
HAVING NB_APPELS_CORTEX > 5
ORDER BY NB_APPELS_CORTEX DESC;

-- 3b. Appels en dehors des heures de bureau (exfiltration ?)
SELECT
    USER_NAME,
    ROLE_NAME,
    LEFT(QUERY_TEXT, 100) AS REQUETE,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TEXT ILIKE '%CORTEX%COMPLETE%'
  AND START_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND (HOUR(START_TIME) < 7 OR HOUR(START_TIME) > 20)
ORDER BY START_TIME DESC
LIMIT 10;

-- 3c. Modèles les plus coûteux (deepseek-r1 consomme plus)
SELECT
    MODEL_NAME AS MODELE,
    COUNT(*) AS NB_APPELS,
    AVG(TOKENS) AS TOKENS_MOYEN,
    AVG(TOKEN_CREDITS) AS CREDITS_MOYEN,
    SUM(TOKEN_CREDITS) AS CREDITS_TOTAL
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY MODEL_NAME
ORDER BY CREDITS_TOTAL DESC;


-- ════════════════════════════════════════════════════════════
-- ACTE 4 : LIMITES BUDGÉTAIRES — CONTRÔLE DE LA DÉPENSE
-- ════════════════════════════════════════════════════════════

-- 4a. Paramètres budget Cortex Code
SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- 4b. Limiter un utilisateur à N crédits/jour :
-- ALTER USER PIERREADM SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
-- ALTER USER PIERREADM SET CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;

-- 4c. Désactiver Cortex Code pour un utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 0;

-- En production : combiner avec un ALERT Snowflake pour
-- notifier quand un utilisateur dépasse un seuil.


-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2E — FERMER LA BOUCLE                       │
-- │                                                          │
-- │  classify → protect → use → MONITOR → refine             │
-- │                                                          │
-- │  3 niveaux de monitoring :                               │
-- │   1. CORTEX_AISQL_USAGE_HISTORY   → détail par appel     │
-- │   2. CORTEX_AI_FUNCTIONS_*        → avec rôles utilisés  │
-- │   3. QUERY_HISTORY                → temps réel           │
-- │                                                          │
-- │  Patterns de détection :                                 │
-- │   • Spike d'appels par heure/utilisateur                 │
-- │   • Utilisation hors heures de bureau                    │
-- │   • Modèles coûteux surconsommés                         │
-- │                                                          │
-- │  Contrôles budgétaires :                                 │
-- │   • CORTEX_CODE_*_DAILY_EST_CREDIT_LIMIT_PER_USER        │
-- └───────────────────────────────────────────────────────────┘

-- ============================================================
-- FIN DU MODULE 2 — LES 3 DIMENSIONS SONT COUVERTES
-- ============================================================
--
-- DIMENSION 1 (matin) : Classify → Tag → Mask → RAP → RBAC
-- DIMENSION 2 (2A+2B) : Cross-Region, Allowlist, Model RBAC, Feature Access
-- DIMENSION 3 (2D+2E) : AI_REDACT (sécurité complémentaire) + Monitoring
--
-- LA PREUVE (2C) : chaque contrôle du matin se transmet à l'AI.
--
-- « La gouvernance n'est pas héritée. Elle est résolue. »
-- ============================================================
