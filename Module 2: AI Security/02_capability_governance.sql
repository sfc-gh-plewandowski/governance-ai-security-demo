-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- Dimension 2 : qui peut utiliser quel modèle, quel agent,
-- quels outils. On ne contrôle pas juste les DONNÉES (Dim 1),
-- on contrôle aussi les CAPACITÉS AI elles-mêmes.
--
-- 3 leviers de contrôle :
--   1. MODEL ALLOWLIST   → quels modèles existent dans le compte
--   2. MODEL RBAC        → quels rôles peuvent appeler quels modèles
--   3. CROSS-REGION      → dans quelles régions l'inférence peut tourner
--
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- A. MODEL ALLOWLIST — QUELS MODÈLES SONT DISPONIBLES
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

-- Vérifions qu'un modèle fonctionne avec la config actuelle (ALL)
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français, en une seule phrase.'
) AS TEST_MODELE_DISPONIBLE;

-- ════════════════════════════════════════════════════════════
-- B. RESTRICTION DE L'ALLOWLIST — LIVE DEMO
-- ════════════════════════════════════════════════════════════
-- On restreint le compte à un seul modèle.
-- Tout le reste devient invisible.

ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2';

-- ✅ Ce modèle est dans l'allowlist → fonctionne
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français.'
) AS MODELE_AUTORISE;

-- ❌ Ce modèle N'EST PAS dans l'allowlist → erreur attendue :
--    "Unknown model llama3.1-70b"
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b',
  'Dis bonjour en français.'
) AS MODELE_BLOQUE;

-- CE QU'ON DÉMONTRE :
-- L'allowlist est un filtre au niveau COMPTE. Seuls les modèles
-- listés peuvent être appelés. Tout le reste est invisible.
-- C'est le premier niveau de gouvernance AI.

-- BONNE PRATIQUE en production : lister uniquement les modèles
-- validés par l'équipe sécurité, par exemple :
-- ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2,llama3.1-70b';

-- ⚠️ IMPORTANT : remettre ALL pour la suite du workshop
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';

-- ════════════════════════════════════════════════════════════
-- C. MODEL RBAC — CONTRÔLE PAR RÔLE (APPLICATION ROLES)
-- ════════════════════════════════════════════════════════════
-- L'allowlist (section B) contrôle quels modèles EXISTENT
-- dans le compte. Le RBAC contrôle quels RÔLES peuvent les
-- appeler. Ce sont deux niveaux complémentaires.

SHOW APPLICATION ROLES IN APPLICATION SNOWFLAKE;

-- Le rôle clé : CORTEX_MODELS_ADMIN
-- Seul ce rôle (et ses parents) peut modifier l'allowlist
-- et gérer l'accès aux modèles.
SHOW GRANTS OF APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN;

-- BONNE PRATIQUE : LEAST PRIVILEGE POUR L'AI
--
-- 1. Allowlist restreinte au niveau compte :
--    ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2,llama3.1-70b';
--    → Seuls ces 2 modèles existent dans le compte.
--
-- 2. Donner CORTEX_MODELS_ADMIN à un rôle spécifique :
--    GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN TO ROLE SECURITY_ADMIN;
--    → Seul SECURITY_ADMIN peut modifier la liste.
--
-- 3. Résultat :
--    • DATA_ANALYST peut appeler mistral-large2 (modèle autorisé)
--    • DATA_ANALYST ne peut PAS ajouter gpt-4o à la liste
--    • Double verrou : l'allowlist dit "quoi", le RBAC dit "qui"

-- ════════════════════════════════════════════════════════════
-- D. CORTEX_ENABLED_CROSS_REGION — CONTRÔLE GÉOGRAPHIQUE
-- ════════════════════════════════════════════════════════════
-- Troisième levier : OÙ l'inférence peut s'exécuter.
-- Certains modèles ne sont pas hébergés dans toutes les régions.
-- Ce paramètre contrôle si Snowflake peut router une requête
-- vers une autre région que celle du compte.

SELECT CURRENT_REGION() AS REGION_ACTUELLE;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- Valeurs possibles :
--   DISABLED    → inférence dans la région du compte uniquement
--   AWS_EU      → AWS Europe (recommandé RGPD pour comptes AWS)
--   AZURE_EU    → Azure Europe (pour comptes Azure)
--   ANY_REGION  → aucune restriction (⚠️ données peuvent transiter hors UE)

-- DÉMONSTRATION : restreindre à AWS_EU
-- Notre compte est sur AWS eu-central-1 (Francfort).
-- Avec AWS_EU, l'inférence reste sur l'infrastructure AWS européenne.

ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

-- ✅ Mistral est hébergé sur AWS → fonctionne
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'En une phrase : où sommes-nous hébergés ?'
) AS MODELE_AWS_OK;

-- ✅ Llama est hébergé sur AWS → fonctionne
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b',
  'En une phrase : dis bonjour.'
) AS MODELE_AWS_OK_2;

-- ❌ Les modèles OpenAI sont hébergés sur Azure.
--    Avec AWS_EU, ils sont hors périmètre → erreur attendue :
--    "Model gpt-4o is unavailable"
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'gpt-4o',
  'Dis bonjour.'
) AS MODELE_AZURE_BLOQUE;

-- CE QU'ON DÉMONTRE :
-- La souveraineté des données s'étend à l'inférence AI.
-- Avec AWS_EU, vos prompts et vos données ne quittent JAMAIS
-- l'infrastructure AWS européenne.
--
-- Pour un compte Azure, c'est l'inverse :
--   AZURE_EU → GPT-4o (Azure) ✅, Anthropic/Mistral (AWS) ❌
--
-- Pour un client finance, santé ou secteur public, c'est la
-- réponse à : "Où partent mes données quand j'appelle un LLM ?"

-- ⚠️ IMPORTANT : remettre ANY_REGION pour la suite du workshop
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- ════════════════════════════════════════════════════════════
-- E. RÉCAPITULATIF — LES 3 LEVIERS
-- ════════════════════════════════════════════════════════════
--
-- ┌─────────────────────┬────────────────────┬──────────────┐
-- │ Levier              │ Contrôle           │ Granularité  │
-- ├─────────────────────┼────────────────────┼──────────────┤
-- │ MODELS_ALLOWLIST    │ Quels modèles      │ Compte       │
-- │ APPLICATION ROLES   │ Qui peut gérer     │ Rôle         │
-- │ CROSS_REGION        │ Où tourne l'infér. │ Compte       │
-- └─────────────────────┴────────────────────┴──────────────┘

-- ════════════════════════════════════════════════════════════
-- F. LIMITES BUDGÉTAIRES CORTEX
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Pour limiter l'utilisation AI par utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
