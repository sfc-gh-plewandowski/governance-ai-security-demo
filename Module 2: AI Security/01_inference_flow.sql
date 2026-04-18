-- ============================================================
-- MODULE 2A — FLUX D'INFÉRENCE AI & FRONTIÈRE DE CONFIANCE
-- ============================================================
-- Ce module couvre :
--   A. Où l'inférence s'exécute (géographie & RGPD)
--   B. Quels modèles sont disponibles (allowlist compte)
--   C. Premier appel Cortex
--   D. Preuve que la gouvernance s'applique avant le modèle
--
-- Pré-requis : Modules 1A–1D exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;


-- ════════════════════════════════════════════════════════════
-- A. OÙ L'INFÉRENCE S'EXÉCUTE — GÉOGRAPHIE & RGPD
-- ════════════════════════════════════════════════════════════
-- CORTEX_ENABLED_CROSS_REGION contrôle si les données
-- peuvent quitter la région du compte pendant l'inférence.
-- Impact direct sur la conformité RGPD.

SELECT CURRENT_REGION() AS REGION_COMPTE;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- Valeurs possibles :
--   DISABLED     → inférence dans la région du compte uniquement
--   AWS_EU       → régions AWS Europe (mTLS entre régions)
--   AZURE_EU     → régions Azure Europe
--   AWS_US       → régions AWS US (⚠ données hors UE)
--   ANY_REGION   → aucune restriction géographique

-- DEMO : restreindre à l'Europe
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

-- ✅ Modèle hébergé sur AWS EU → fonctionne
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'En une phrase, quel est le principe de minimisation des données selon le RGPD ?'
) AS MODELE_AWS_EU_OK;

-- Restaurer
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';


-- ════════════════════════════════════════════════════════════
-- B. QUELS MODÈLES SONT DISPONIBLES — ALLOWLIST COMPTE
-- ════════════════════════════════════════════════════════════
-- CORTEX_MODELS_ALLOWLIST est le premier filtre :
-- seuls les modèles listés sont utilisables, par quiconque.

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

-- DEMO : restreindre à un seul modèle
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'mistral-large2';

-- ✅ autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Dis bonjour en français.'
) AS MODELE_AUTORISE;

-- ❌ bloqué → erreur "Unknown model"
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour en français.'
) AS MODELE_BLOQUE;

-- Restaurer
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';


-- ════════════════════════════════════════════════════════════
-- C. PREMIER APPEL — CORTEX.COMPLETE
-- ════════════════════════════════════════════════════════════
-- Le flux d'inférence :
--   User → Role → SQL (SELECT + CORTEX.COMPLETE)
--   → Gouvernance appliquée (masking, RAP, projection)
--   → Données gouvernées envoyées au modèle
--   → Réponse retournée au user

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Explique en 2 phrases ce qu''est le masking dynamique dans Snowflake.'
) AS REPONSE_AI;


-- ════════════════════════════════════════════════════════════
-- D. LE PONT — LA GOUVERNANCE S'APPLIQUE AVANT LE MODÈLE
-- ════════════════════════════════════════════════════════════
-- Même requête AI sur les mêmes données.
-- Le modèle reçoit ce que le RÔLE voit — pas les données brutes.
-- C'est le pont entre le matin (Dimension 1) et l'après-midi.

USE SECONDARY ROLES NONE;

-- SECURITY_ADMIN : le modèle reçoit permis + IBAN en clair
USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Résume ce profil employé en 2 lignes : ' ||
    'Nom: ' || PRENOM || ' ' || NOM ||
    ', Département: ' || DEPARTEMENT ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 1;

-- DATA_ANALYST : le modèle reçoit des hash SHA2
USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Résume ce profil employé en 2 lignes : ' ||
    'Nom: ' || PRENOM || ' ' || NOM ||
    ', Département: ' || DEPARTEMENT ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 3;

-- RÉSULTAT ATTENDU :
-- SECURITY_ADMIN → le modèle résume avec le vrai permis et IBAN
-- DATA_ANALYST   → le modèle résume avec des "identifiants hashés"
--
-- La gouvernance est appliquée AVANT que le modèle ne voie les données.
-- Le modèle ne peut pas contourner le masking — il n'a jamais
-- accès aux données brutes.


-- ════════════════════════════════════════════════════════════
-- RESET
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2A                                          │
-- │                                                          │
-- │ 1. Cross-Region   → OÙ l'inférence tourne (RGPD)        │
-- │ 2. Model Allowlist → QUELS modèles existent (compte)     │
-- │ 3. Le Pont         → la gouvernance Dim 1 s'applique     │
-- │                      AVANT que le modèle voie les données│
-- │                                                          │
-- │ → Module 2B : QUI peut utiliser QUEL modèle (RBAC AI)   │
-- └───────────────────────────────────────────────────────────┘
