-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- Contrôle granulaire de l'accès AI au niveau rôle :
--   1. Model RBAC         → rôles applicatifs par modèle (GA 2025)
--   2. Feature Access     → database roles par fonctionnalité Cortex
--   3. LLM Privileges     → USE AI FUNCTIONS au niveau compte
--
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;


-- ════════════════════════════════════════════════════════════
-- ACTE 1 : MODEL RBAC — QUEL RÔLE UTILISE QUEL MODÈLE
-- ════════════════════════════════════════════════════════════
-- Depuis avril 2025, chaque modèle a un rôle applicatif.
-- Quand ALLOWLIST = 'None', seuls les rôles applicatifs
-- déterminent l'accès modèle-par-modèle.
--
-- Ordre d'évaluation :
--   1. Le rôle a-t-il un APPLICATION ROLE modèle ? → OK
--   2. Sinon, le modèle est-il dans ALLOWLIST ?    → OK
--   3. Sinon → ACCÈS REFUSÉ
--
-- Best practice production :
--   ALLOWLIST = 'None' + grants applicatifs par rôle

-- 1a. Activer les rôles modèle (obligatoire une première fois)
CALL SNOWFLAKE.MODELS.CORTEX_BASE_MODELS_REFRESH();

-- 1b. Inventaire : combien de rôles modèle existent ?
SHOW APPLICATION ROLES LIKE '%CORTEX-MODEL%' IN APPLICATION SNOWFLAKE;

-- 1c. Qui détient le super-rôle modèle aujourd'hui ?
SHOW GRANTS OF APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN;

-- 1d. SETUP : verrouiller l'allowlist, ouvrir par rôle
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'None';

-- DATA_ANALYST : modèle conversationnel + fonctions managées
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-7B"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE"
  TO ROLE DATA_ANALYST;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-SENTIMENT"
  TO ROLE DATA_ANALYST;

-- DATA_ENGINEER : modèles de raisonnement + code
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  TO ROLE DATA_ENGINEER;
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  TO ROLE DATA_ENGINEER;

-- SECURITY_ADMIN : accès total + gestion
GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ALL"
  TO ROLE SECURITY_ADMIN;
GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN
  TO ROLE SECURITY_ADMIN;


-- 1e. TEST — changer de rôle et vérifier


USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;


-- ✅ mistral-large2 autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'En une phrase : pourquoi le least privilege est important pour l''AI ?'
) AS ANALYST_MISTRAL_OK;

-- ❌ deepseek-r1 NON autorisé → erreur
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1',
  'En une phrase : pourquoi le least privilege est important pour l''AI ?'
) AS ANALYST_DEEPSEEK_BLOQUE;

-- ✅ AI_TRANSLATE utilise arctic-translate (autorisé)
SELECT SNOWFLAKE.CORTEX.AI_TRANSLATE(
  'Data governance is essential for AI security.', 'en', 'fr'
) AS ANALYST_TRANSLATE_OK;


USE ROLE DATA_ENGINEER;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ llama3.1-70b autorisé pour DATA_ENGINEER
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b',
  'En une phrase : qu''est-ce que le model RBAC ?'
) AS ENGINEER_LLAMA_OK;


USE ROLE SECURITY_ADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ✅ accès total via CORTEX-MODEL-ROLE-ALL
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'deepseek-r1', 'Bonjour depuis SECURITY_ADMIN.'
) AS SECADMIN_TOUT_OK;


-- 1f. NETTOYAGE Acte 1
USE ROLE ACCOUNTADMIN;

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';

REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-LARGE2"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-MISTRAL-7B"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-LLAMA3.1-70B"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE"
  FROM ROLE DATA_ANALYST;
REVOKE APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-ARCTIC-SENTIMENT"
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
-- ACTE 2 : FEATURE ACCESS — QUEL RÔLE UTILISE QUELLE FEATURE
-- ════════════════════════════════════════════════════════════
-- 5 database roles dans la database SNOWFLAKE :
--   CORTEX_USER         → accès complet Cortex (PUBLIC par défaut)
--   AI_FUNCTIONS_USER   → fonctions AI scalaires uniquement
--   CORTEX_AGENT_USER   → Cortex Agents uniquement
--   CORTEX_EMBED_USER   → embedding uniquement
--   COPILOT_USER        → Cortex Code (PUBLIC par défaut)
--
-- Cas d'usage production : un analyste n'a pas besoin de
-- créer des agents. Un data engineer n'a pas besoin de
-- Cortex Code. Least privilege par fonctionnalité.

-- 2a. État actuel : qui a quoi ?
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.CORTEX_EMBED_USER;
SHOW GRANTS OF DATABASE ROLE SNOWFLAKE.COPILOT_USER;

-- 2b. DEMO : segmenter l'accès par fonctionnalité

-- Retirer l'accès global Cortex de PUBLIC
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC;

-- DATA_ANALYST → fonctions AI scalaires seulement (pas agents, pas search)
GRANT DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER TO ROLE DATA_ANALYST;

-- DATA_ENGINEER → fonctions AI + agents + embedding
GRANT DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER TO ROLE DATA_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE DATA_ENGINEER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_EMBED_USER TO ROLE DATA_ENGINEER;

-- SECURITY_ADMIN → accès complet Cortex
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SECURITY_ADMIN;

-- 2c. TEST
USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ✅ AI function scalaire → OK (AI_FUNCTIONS_USER suffit)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Bonjour — test feature access DATA_ANALYST.'
) AS ANALYST_AI_FUNCTION_OK;

USE ROLE DATA_ENGINEER;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ✅ AI function scalaire → OK
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Bonjour — test feature access DATA_ENGINEER.'
) AS ENGINEER_AI_FUNCTION_OK;

-- ✅ Embedding → OK (CORTEX_EMBED_USER)
SELECT SNOWFLAKE.CORTEX.EMBED_TEXT_1024(
  'snowflake-arctic-embed-l-v2.0',
  'Test embedding pour DATA_ENGINEER.'
) AS ENGINEER_EMBED_OK;


-- 2d. NETTOYAGE Acte 2
USE ROLE ACCOUNTADMIN;

REVOKE DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER FROM ROLE DATA_ANALYST;
REVOKE DATABASE ROLE SNOWFLAKE.AI_FUNCTIONS_USER FROM ROLE DATA_ENGINEER;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER FROM ROLE DATA_ENGINEER;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_EMBED_USER FROM ROLE DATA_ENGINEER;
REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE SECURITY_ADMIN;

-- Restaurer l'accès global
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE PUBLIC;


-- ════════════════════════════════════════════════════════════
-- ACTE 3 : LLM PRIVILEGES — USE AI FUNCTIONS ON ACCOUNT
-- ════════════════════════════════════════════════════════════
-- Privilège de niveau COMPTE, indépendant des database roles.
-- Par défaut : USE AI FUNCTIONS est GRANTED à PUBLIC.
--
-- Un utilisateur a besoin des DEUX pour appeler une fonction AI :
--   1. USE AI FUNCTIONS ON ACCOUNT  (account-level privilege)
--   2. CORTEX_USER ou AI_FUNCTIONS_USER (database role)
--
-- Si l'un des deux manque → accès refusé.
-- USE AI FUNCTIONS ne contrôle PAS quel modèle est accessible.
-- C'est un interrupteur général ON/OFF pour les fonctions AI.
--
-- Géré uniquement par ACCOUNTADMIN.

-- 3a. Vérifier l'état actuel du privilège
SHOW GRANTS ON ACCOUNT;
-- Chercher la ligne : USE AI FUNCTIONS | ROLE | PUBLIC

-- 3b. DEMO : révoquer USE AI FUNCTIONS de PUBLIC
-- Après cette révocation, même un rôle avec CORTEX_USER
-- ne pourra plus appeler de fonction AI.
REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE PUBLIC;

-- 3c. TEST — DATA_ANALYST a toujours CORTEX_USER (via PUBLIC hérité)
-- mais n'a plus USE AI FUNCTIONS → bloqué
USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ❌ Bloqué : USE AI FUNCTIONS manquant
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Ce message ne devrait pas passer — USE AI FUNCTIONS révoqué.'
) AS ANALYST_BLOQUE_SANS_PRIVILEGE;

-- 3d. Accorder USE AI FUNCTIONS à des rôles spécifiques
USE ROLE ACCOUNTADMIN;

GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE DATA_ANALYST;
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE DATA_ENGINEER;
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE SECURITY_ADMIN;

-- 3e. TEST — DATA_ANALYST a maintenant USE AI FUNCTIONS → OK
USE ROLE DATA_ANALYST;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ✅ USE AI FUNCTIONS restauré pour ce rôle
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'USE AI FUNCTIONS rétabli — l''accès fonctionne.'
) AS ANALYST_PRIVILEGE_RESTAURE;

-- 3f. NETTOYAGE Acte 3
USE ROLE ACCOUNTADMIN;

REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE DATA_ANALYST;
REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE DATA_ENGINEER;
REVOKE USE AI FUNCTIONS ON ACCOUNT FROM ROLE SECURITY_ADMIN;

-- Restaurer l'accès global
GRANT USE AI FUNCTIONS ON ACCOUNT TO ROLE PUBLIC;


-- ════════════════════════════════════════════════════════════
-- RESET
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;


-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2B — DIMENSION 2 : GOUVERNANCE CAPACITÉS    │
-- │                                                          │
-- │  Acte 1 — Model RBAC (rôles applicatifs)                 │
-- │   • ALLOWLIST = 'None' + grants par rôle = least priv.   │
-- │   • DATA_ANALYST : mistral-large2 + fonctions managées   │
-- │   • DATA_ENGINEER : + deepseek-r1 (raisonnement)         │
-- │   • SECURITY_ADMIN : CORTEX-MODEL-ROLE-ALL + admin       │
-- │                                                          │
-- │  Acte 2 — Feature Access (database roles)                │
-- │   • CORTEX_USER retiré de PUBLIC                         │
-- │   • Chaque rôle reçoit les features nécessaires          │
-- │   • AI_FUNCTIONS_USER, CORTEX_AGENT_USER,                │
-- │     CORTEX_EMBED_USER = segmentation fine                │
-- │                                                          │
-- │  Acte 3 — LLM Privileges (account-level)                 │
-- │   • USE AI FUNCTIONS ON ACCOUNT = interrupteur global     │
-- │   • Requis EN PLUS des database roles                    │
-- │   • Révocation de PUBLIC → grant ciblé par rôle          │
-- │                                                          │
-- │  → Module 2C : AI_REDACT — contrôles probabilistes       │
-- └───────────────────────────────────────────────────────────┘
