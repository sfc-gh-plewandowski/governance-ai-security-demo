-- ============================================================
-- MODULE 2C — PREUVE QUE LA GOUVERNANCE SE TRANSMET À L'IA
-- ============================================================
-- C'est LE moment de l'après-midi. On prouve que tout ce
-- qu'on a construit le matin (masking, RAP, projection)
-- est respecté quand Cortex AI interroge les données.
--
-- Le modèle ne voit que ce que le rôle voit.
-- Même requête AI, résultats différents selon le rôle.
--
-- Pré-requis : Modules 1A–1C + 2A + 2B exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ════════════════════════════════════════════════════════════
-- PREUVE 1 : LE MASKING SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────
-- A. SECURITY_ADMIN — LE MODÈLE REÇOIT LES DONNÉES EN CLAIR
-- ────────────────────────────────────────────────────────────

USE ROLE SECURITY_ADMIN;

SELECT
  'SECURITY_ADMIN' AS ROLE_ACTIF,
  PRENOM, NOM,
  PERMIS_CONDUIRE AS PERMIS_VU_PAR_LE_ROLE,
  IBAN AS IBAN_VU_PAR_LE_ROLE,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici un profil employé. Résume en 1 phrase ce que tu vois : ' ||
    'Prénom: ' || PRENOM ||
    ', Nom: ' || NOM ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN ||
    ', Date naissance: ' || DATE_NAISSANCE::STRING
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 1;

-- ────────────────────────────────────────────────────────────
-- B. DATA_ANALYST — LE MODÈLE REÇOIT DES HASH
-- ────────────────────────────────────────────────────────────

USE ROLE DATA_ANALYST;

SELECT
  'DATA_ANALYST' AS ROLE_ACTIF,
  PRENOM, NOM,
  PERMIS_CONDUIRE AS PERMIS_VU_PAR_LE_ROLE,
  IBAN AS IBAN_VU_PAR_LE_ROLE,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici un profil employé. Résume en 1 phrase ce que tu vois : ' ||
    'Prénom: ' || PRENOM ||
    ', Nom: ' || NOM ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN ||
    ', Date naissance: ' || DATE_NAISSANCE::STRING
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 3;

-- ATTENDU :
-- SECURITY_ADMIN → le modèle mentionne le vrai permis (8813963792) et IBAN (FR76...)
-- DATA_ANALYST   → le modèle mentionne des "identifiants hashés" ou "données chiffrées"
-- LE MODÈLE NE VOIT QUE CE QUE LE RÔLE VOIT

-- ════════════════════════════════════════════════════════════
-- PREUVE 2 : LA RAP SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────
-- C. COMBIEN D'EMPLOYÉS LE MODÈLE "CONNAÎT" PAR RÔLE ?
-- ────────────────────────────────────────────────────────────

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici une liste de ' || COUNT(*)::STRING || ' employés de Voltaire Analytics. ' ||
    'Les départements représentés sont : ' ||
    LISTAGG(DISTINCT DEPARTEMENT, ', ') ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici une liste de ' || COUNT(*)::STRING || ' employés de Voltaire Analytics. ' ||
    'Les départements représentés sont : ' ||
    LISTAGG(DISTINCT DEPARTEMENT, ', ') ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

-- ATTENDU :
-- SECURITY_ADMIN → "1000 employés dans 15 départements"
-- DATA_ANALYST   → "208 employés dans Commercial, Marketing, Communication"
-- LE MODÈLE NE CONNAÎT QUE LES LIGNES AUTORISÉES PAR LA RAP

-- ════════════════════════════════════════════════════════════
-- PREUVE 3 : LA PROJECTION SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────
-- D. DATA_ANALYST NE PEUT PAS PASSER LE NIR AU MODÈLE
-- ────────────────────────────────────────────────────────────

USE ROLE DATA_ANALYST;

-- DÉCOMMENTER POUR DÉMONTRER L'ERREUR :
-- SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
--   'NIR de l''employé : ' || NIR
-- ) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL WHERE EMPLOYE_ID = 3;

-- Erreur attendue :
-- "The following columns are restricted by a Projection Policy: NIR"
-- → Même via CORTEX.COMPLETE, la projection policy bloque l'accès

-- ════════════════════════════════════════════════════════════
-- PREUVE 4 : CRM — LE MASKING SUR SIRET/SIREN SE TRANSMET
-- ════════════════════════════════════════════════════════════

-- ────────────────────────────────────────────────────────────
-- E. COMPARAISON CRM ENTRE RÔLES
-- ────────────────────────────────────────────────────────────

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  RAISON_SOCIALE, SIRET,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Identifie cette entreprise : ' || RAISON_SOCIALE ||
    ', SIRET: ' || SIRET ||
    ', Secteur: ' || SECTEUR_ACTIVITE ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES
WHERE ENTREPRISE_ID = 1;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  RAISON_SOCIALE, SIRET,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Identifie cette entreprise : ' || RAISON_SOCIALE ||
    ', SIRET: ' || SIRET ||
    ', Secteur: ' || SECTEUR_ACTIVITE ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES
WHERE ENTREPRISE_ID = 1;

-- ATTENDU :
-- SECURITY_ADMIN → mentionne le vrai SIRET (89623379046048)
-- DATA_ANALYST   → mentionne un hash SHA2 au lieu du SIRET

-- ────────────────────────────────────────────────────────────
-- F. RESET
-- ────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;
