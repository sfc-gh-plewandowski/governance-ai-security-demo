-- CERT: D5 Securing AI/ML (12%) — trust boundary, projection proof, inference flow
-- ============================================================
-- MODULE 2A — FLUX D'INFÉRENCE AI & FRONTIÈRE DE CONFIANCE
-- ============================================================
-- Ce module couvre :
--   A. Où l'inférence s'exécute (géographie & RGPD)
--   B. Quels modèles sont disponibles (allowlist compte)
--   C. Le masking s'applique avant le modèle (colonnes maskées)
--   D. La RAP s'applique avant le modèle (domaines invisibles)
--   E. La projection bloque l'accès même via CORTEX.COMPLETE
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

-- ❌ Modèle hébergé ailleurs → erreur
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'openai-gpt-5.2', -- utiliser openai si compte AWS / anthropic si compte Azure 
  'En une phrase, quel est le principe de minimisation des données selon le RGPD ?'
) AS MODELE_AZURE_ERROR;

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

USE ROLE SECURITY_ADMIN;
USE SECONDARY ROLES NONE;

-- ✅ autorisé
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2', 'Dis bonjour en français.'
) AS MODELE_AUTORISE;

-- ❌ bloqué → erreur "Unknown model"
SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'llama3.1-70b', 'Dis bonjour en français.'
) AS MODELE_BLOQUE;

-- Restaurer
USE ROLE ACCOUNTADMIN;
ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';


-- ════════════════════════════════════════════════════════════
-- C. LE MASKING S'APPLIQUE AVANT LE MODÈLE
-- ════════════════════════════════════════════════════════════
-- Le modèle reçoit ce que le RÔLE voit — pas les données brutes.
-- Flux : User → Role → SQL + gouvernance → données maskées → modèle

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
-- Le modèle ne peut pas contourner le masking.


-- ════════════════════════════════════════════════════════════
-- D. LA RAP S'APPLIQUE AVANT LE MODÈLE — DOMAINES INVISIBLES
-- ════════════════════════════════════════════════════════════
-- La Row Access Policy filtre les lignes AVANT l'inférence.
-- Si un rôle n'a pas accès à un département ou un secteur,
-- le modèle ne sait même pas que ces données existent.
--
-- Rappel RAP_DEPARTEMENT (Module 1C) :
--   SECURITY_ADMIN → tous les départements (1000 employés)
--   DATA_ANALYST   → Commercial, Marketing, Communication (~208)
--   DATA_ENGINEER  → Informatique, R&D, Production (~200)

-- SECURITY_ADMIN : le modèle voit TOUS les départements
USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  LISTAGG(DISTINCT DEPARTEMENT, ', ') AS DEPARTEMENTS_VISIBLES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Dans le département Informatique de Voltaire Analytics, il y a ' ||
    (SELECT COUNT(*) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL WHERE DEPARTEMENT = 'Informatique')::STRING ||
    ' employés. Résume en 1 phrase.'
  ) AS RESUME_DEPT_INFORMATIQUE;

-- DATA_ANALYST : le département Informatique est INVISIBLE
USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  LISTAGG(DISTINCT DEPARTEMENT, ', ') AS DEPARTEMENTS_VISIBLES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Dans le département Informatique de Voltaire Analytics, il y a ' ||
    (SELECT COUNT(*) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL WHERE DEPARTEMENT = 'Informatique')::STRING ||
    ' employés. Résume en 1 phrase.'
  ) AS RESUME_DEPT_INFORMATIQUE;

-- RÉSULTAT ATTENDU :
-- SECURITY_ADMIN → "~67 employés dans le département Informatique"
-- DATA_ANALYST   → "0 employés dans le département Informatique"
--   Le modèle reçoit 0 car la RAP filtre le département Informatique.
--   Le modèle ne sait pas que ce département existe.
--
-- Même observation sur le CRM (RAP_SECTEUR) :
-- DATA_ANALYST ne voit que Banque & Finance, Assurance, Conseil.
-- DATA_ENGINEER ne voit que Technologie, Télécommunications, Industrie.


-- ════════════════════════════════════════════════════════════
-- E. LA PROJECTION BLOQUE L'ACCÈS MÊME VIA CORTEX.COMPLETE
-- ════════════════════════════════════════════════════════════
-- La projection policy bloque l'accès à une colonne entière.
-- Même CORTEX.COMPLETE ne peut pas lire la colonne — l'erreur
-- se produit au niveau SQL, avant que le modèle n'entre en jeu.

USE ROLE DATA_ANALYST;

-- DÉCOMMENTER POUR DÉMONTRER L'ERREUR :
-- SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
--   'Voici le NIR de l''employé : ' || NIR
-- ) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL WHERE EMPLOYE_ID = 3;

-- Erreur attendue :
-- "The following columns are restricted by a Projection Policy: NIR"
-- La colonne est invisible au niveau SQL — le modèle ne peut
-- jamais y accéder, même indirectement via une fonction AI.


-- ════════════════════════════════════════════════════════════
-- RESET
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2A                                          │
-- │                                                          │
-- │ A. Cross-Region   → OÙ l'inférence tourne (RGPD)        │
-- │ B. Model Allowlist → QUELS modèles existent (compte)     │
-- │ C. Masking → AI    → colonnes maskées avant le modèle    │
-- │ D. RAP → AI        → domaines invisibles pour le modèle  │
-- │ E. Projection → AI → colonne entièrement bloquée         │
-- │                                                          │
-- │ → Module 2B : QUI peut utiliser QUEL modèle (RBAC AI)   │
-- └───────────────────────────────────────────────────────────┘
