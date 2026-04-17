-- ============================================================
-- MODULE 1C — ÉTAPE 1 : ROW ACCESS POLICIES
-- ============================================================
-- Une Row Access Policy (RAP) filtre les LIGNES au moment de
-- la requête. L'utilisateur ne sait même pas que des lignes
-- manquent — il voit juste un résultat plus petit.
--
-- Deux patterns :
--   1. Hardcoded : vérifie le rôle directement (rapide, rigide)
--   2. Mapping table : table d'habilitations (scalable, auditable)
--
-- Pré-requis : Module 1A + 1B exécutés, rôles créés dans 1B/04
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. PATTERN 1 — RAP HARDCODÉE (démo rapide)
-- ────────────────────────────────────────────────────────────
-- Seul SECURITY_ADMIN voit tous les départements.
-- DATA_ANALYST voit uniquement Commercial + Marketing.
-- DATA_ENGINEER voit uniquement Informatique + R&D.

CREATE OR REPLACE ROW ACCESS POLICY VOLTAIRE_GOVERNANCE.POLICIES.RAP_DEPARTEMENT
AS (dept VARCHAR)
RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('SECURITY_ADMIN')
  OR (IS_ROLE_IN_SESSION('DATA_ANALYST') AND dept IN ('Commercial', 'Marketing', 'Communication'))
  OR (IS_ROLE_IN_SESSION('DATA_ENGINEER') AND dept IN ('Informatique', 'Recherche & Développement', 'Production'));

ALTER TABLE VOLTAIRE_RH.EMPLOYES.PERSONNEL
  ADD ROW ACCESS POLICY VOLTAIRE_GOVERNANCE.POLICIES.RAP_DEPARTEMENT
  ON (DEPARTEMENT);

-- ────────────────────────────────────────────────────────────
-- B. VÉRIFICATION RAPIDE — COMBIEN DE LIGNES PAR RÔLE ?
-- ────────────────────────────────────────────────────────────

USE SECONDARY ROLES NONE;

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_TEST, COUNT(*) AS LIGNES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_TEST, COUNT(*) AS LIGNES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

USE ROLE DATA_ENGINEER;
SELECT 'DATA_ENGINEER' AS ROLE_TEST, COUNT(*) AS LIGNES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

-- ────────────────────────────────────────────────────────────
-- C. PATTERN 2 — TABLE D'HABILITATIONS (production-grade)
-- ────────────────────────────────────────────────────────────
-- En production, on ne hardcode pas les départements.
-- On utilise une table de mapping : quel rôle voit quel secteur.

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

CREATE OR REPLACE TABLE VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR (
    ROLE_NAME       STRING,
    SECTEUR_AUTORISE STRING
);

INSERT INTO VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR VALUES
  ('DATA_ANALYST', 'Banque & Finance'),
  ('DATA_ANALYST', 'Assurance'),
  ('DATA_ANALYST', 'Conseil'),
  ('DATA_ENGINEER', 'Technologie'),
  ('DATA_ENGINEER', 'Télécommunications'),
  ('DATA_ENGINEER', 'Industrie'),
  ('GLOBAL_VIEWER', 'Banque & Finance'),
  ('GLOBAL_VIEWER', 'Assurance'),
  ('GLOBAL_VIEWER', 'Conseil'),
  ('GLOBAL_VIEWER', 'Technologie'),
  ('GLOBAL_VIEWER', 'Télécommunications'),
  ('GLOBAL_VIEWER', 'Industrie'),
  ('GLOBAL_VIEWER', 'Santé'),
  ('GLOBAL_VIEWER', 'Luxe'),
  ('GLOBAL_VIEWER', 'Distribution');

GRANT SELECT ON TABLE VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR
  TO ROLE DATA_ANALYST;
GRANT SELECT ON TABLE VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR
  TO ROLE DATA_ENGINEER;
GRANT SELECT ON TABLE VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR
  TO ROLE SECURITY_ADMIN;
GRANT USAGE ON DATABASE VOLTAIRE_GOVERNANCE TO ROLE DATA_ANALYST;
GRANT USAGE ON DATABASE VOLTAIRE_GOVERNANCE TO ROLE DATA_ENGINEER;
GRANT USAGE ON DATABASE VOLTAIRE_GOVERNANCE TO ROLE SECURITY_ADMIN;
GRANT USAGE ON SCHEMA VOLTAIRE_GOVERNANCE.POLICIES TO ROLE DATA_ANALYST;
GRANT USAGE ON SCHEMA VOLTAIRE_GOVERNANCE.POLICIES TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA VOLTAIRE_GOVERNANCE.POLICIES TO ROLE SECURITY_ADMIN;

-- ────────────────────────────────────────────────────────────
-- D. RAP AVEC MAPPING TABLE
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE ROW ACCESS POLICY VOLTAIRE_GOVERNANCE.POLICIES.RAP_SECTEUR
AS (secteur VARCHAR)
RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('SECURITY_ADMIN')
  OR EXISTS (
    SELECT 1 FROM VOLTAIRE_GOVERNANCE.POLICIES.HABILITATIONS_SECTEUR
    WHERE ROLE_NAME = CURRENT_ROLE()
      AND SECTEUR_AUTORISE = secteur
  );

ALTER TABLE VOLTAIRE_CRM.CLIENTS.ENTREPRISES
  ADD ROW ACCESS POLICY VOLTAIRE_GOVERNANCE.POLICIES.RAP_SECTEUR
  ON (SECTEUR_ACTIVITE);

-- ────────────────────────────────────────────────────────────
-- E. VÉRIFICATION — MAPPING TABLE PATTERN
-- ────────────────────────────────────────────────────────────

USE SECONDARY ROLES NONE;

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_TEST, COUNT(*) AS ENTREPRISES,
  COUNT(DISTINCT SECTEUR_ACTIVITE) AS SECTEURS
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_TEST, COUNT(*) AS ENTREPRISES,
  COUNT(DISTINCT SECTEUR_ACTIVITE) AS SECTEURS,
  LISTAGG(DISTINCT SECTEUR_ACTIVITE, ', ') AS SECTEURS_VISIBLES
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES;

USE ROLE DATA_ENGINEER;
SELECT 'DATA_ENGINEER' AS ROLE_TEST, COUNT(*) AS ENTREPRISES,
  COUNT(DISTINCT SECTEUR_ACTIVITE) AS SECTEURS,
  LISTAGG(DISTINCT SECTEUR_ACTIVITE, ', ') AS SECTEURS_VISIBLES
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES;

-- ────────────────────────────────────────────────────────────
-- F. RESET — retour à la normale
-- ────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;
