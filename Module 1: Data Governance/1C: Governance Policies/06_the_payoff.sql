-- ============================================================
-- MODULE 1C — ÉTAPE 6 : LE MOMENT DE VÉRITÉ (THE PAYOFF)
-- ============================================================
-- Même requête, 4 rôles différents.
-- Tout ce qu'on a construit (classification + RBAC + masking
-- + projection + RAP) se manifeste en une seule démonstration.
--
-- Pré-requis : Modules 1A + 1B + 1C (01-05) exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;

-- ────────────────────────────────────────────────────────────
-- A. LA REQUÊTE DE RÉFÉRENCE
-- ────────────────────────────────────────────────────────────
-- On va exécuter cette même requête avec chaque rôle :

-- SELECT EMPLOYE_ID, PRENOM, NOM, DEPARTEMENT, POSTE,
--        PERMIS_CONDUIRE, IBAN, DATE_NAISSANCE
-- FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
-- LIMIT 10;

-- ────────────────────────────────────────────────────────────
-- B. SECURITY_ADMIN — ACCÈS COMPLET
-- ────────────────────────────────────────────────────────────

USE ROLE SECURITY_ADMIN;

SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  EMPLOYE_ID, PRENOM, NOM, DEPARTEMENT, POSTE,
  PERMIS_CONDUIRE, IBAN, DATE_NAISSANCE
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
LIMIT 10;

-- Attendu : toutes les lignes, toutes les colonnes, toutes les valeurs en clair

-- ────────────────────────────────────────────────────────────
-- C. DATA_ANALYST — MASKING + RAP
-- ────────────────────────────────────────────────────────────

USE ROLE DATA_ANALYST;

SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  EMPLOYE_ID, PRENOM, NOM, DEPARTEMENT, POSTE,
  PERMIS_CONDUIRE, IBAN, DATE_NAISSANCE
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
LIMIT 10;

-- Attendu :
--   • LIGNES : seulement Commercial, Marketing, Communication (RAP)
--   • PERMIS_CONDUIRE : hash SHA2 (tag-based masking)
--   • IBAN : hash SHA2 (tag-based masking)
--   • DATE_NAISSANCE : 1er janvier de l'année (MASK_DATE_SENSIBLE)

-- ────────────────────────────────────────────────────────────
-- D. DATA_ENGINEER — MASKING + RAP (différents périmètres)
-- ────────────────────────────────────────────────────────────

USE ROLE DATA_ENGINEER;

SELECT 'DATA_ENGINEER' AS ROLE_ACTIF,
  EMPLOYE_ID, PRENOM, NOM, DEPARTEMENT, POSTE,
  PERMIS_CONDUIRE, IBAN, DATE_NAISSANCE
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
LIMIT 10;

-- Attendu :
--   • LIGNES : seulement Informatique, R&D, Production (RAP)
--   • PERMIS_CONDUIRE : '***MASQUÉ***' (ni SECURITY_ADMIN ni DATA_ANALYST)
--   • IBAN : '***MASQUÉ***'
--   • DATE_NAISSANCE : NULL

-- ────────────────────────────────────────────────────────────
-- E. CRM — MÊME DÉMONSTRATION AVEC LA TABLE ENTREPRISES
-- ────────────────────────────────────────────────────────────

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  COUNT(*) AS NB_ENTREPRISES,
  COUNT(DISTINCT SECTEUR_ACTIVITE) AS NB_SECTEURS
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  COUNT(*) AS NB_ENTREPRISES,
  COUNT(DISTINCT SECTEUR_ACTIVITE) AS NB_SECTEURS,
  LISTAGG(DISTINCT SECTEUR_ACTIVITE, ', ') AS SECTEURS_VISIBLES
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES;

-- ────────────────────────────────────────────────────────────
-- F. SYNTHÈSE — MATRICE DE COUVERTURE
-- ────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

SELECT 'MASKING' AS TYPE_PROTECTION, COUNT(*) AS NB_COLONNES
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'VOLTAIRE_RH.EMPLOYES.PERSONNEL', REF_ENTITY_DOMAIN => 'TABLE'))
WHERE POLICY_KIND = 'MASKING_POLICY'
UNION ALL
SELECT 'PROJECTION', COUNT(*)
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'VOLTAIRE_RH.EMPLOYES.PERSONNEL', REF_ENTITY_DOMAIN => 'TABLE'))
WHERE POLICY_KIND = 'PROJECTION_POLICY'
UNION ALL
SELECT 'ROW ACCESS', COUNT(*)
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_NAME => 'VOLTAIRE_RH.EMPLOYES.PERSONNEL', REF_ENTITY_DOMAIN => 'TABLE'))
WHERE POLICY_KIND = 'ROW_ACCESS_POLICY';
