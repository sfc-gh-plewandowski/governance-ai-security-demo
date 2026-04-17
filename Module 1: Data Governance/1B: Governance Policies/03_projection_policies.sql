-- ============================================================
-- MODULE 1B — ÉTAPE 3 : POLITIQUES DE PROJECTION
-- ============================================================
-- Une projection policy empêche une colonne d'apparaître
-- dans les résultats. Plus fort que le masking : la colonne
-- n'est même pas visible dans un SELECT *.
--
-- Cas d'usage : notes internes, champs médico-légaux,
-- commentaires managers, colonnes techniques sensibles.
--
-- Pré-requis : 01_masking_policies.sql exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. POLITIQUE DE PROJECTION — COLONNES RESTREINTES
-- ────────────────────────────────────────────────────────────
-- Seul SECURITY_ADMIN peut voir la colonne.
-- Tous les autres rôles : la colonne est exclue du résultat.

CREATE OR REPLACE PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_STRICT
AS () RETURNS PROJECTION_CONSTRAINT ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN PROJECTION_CONSTRAINT(ALLOW => true)
    ELSE PROJECTION_CONSTRAINT(ALLOW => false)
  END;

-- ────────────────────────────────────────────────────────────
-- B. POLITIQUE DE PROJECTION — COLONNES INTERNES
-- ────────────────────────────────────────────────────────────
-- DATA_ENGINEER et SECURITY_ADMIN peuvent voir.
-- Les autres non.

CREATE OR REPLACE PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_INTERNE
AS () RETURNS PROJECTION_CONSTRAINT ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN PROJECTION_CONSTRAINT(ALLOW => true)
    WHEN IS_ROLE_IN_SESSION('DATA_ENGINEER') THEN PROJECTION_CONSTRAINT(ALLOW => true)
    ELSE PROJECTION_CONSTRAINT(ALLOW => false)
  END;

-- ────────────────────────────────────────────────────────────
-- C. ATTACHER AUX COLONNES SENSIBLES
-- ────────────────────────────────────────────────────────────

ALTER TABLE VOLTAIRE_RH.EMPLOYES.PERSONNEL MODIFY COLUMN
  NIR SET PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_STRICT;

ALTER TABLE VOLTAIRE_RH.EMPLOYES.PERSONNEL MODIFY COLUMN
  NUMERO_PASSEPORT SET PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_STRICT;

ALTER TABLE VOLTAIRE_RH.RECRUTEMENT.CANDIDATS MODIFY COLUMN
  SALAIRE_SOUHAITE SET PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_INTERNE;

ALTER TABLE VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS MODIFY COLUMN
  PAYLOAD SET PROJECTION POLICY VOLTAIRE_GOVERNANCE.POLICIES.HIDE_COLUMN_INTERNE;

-- ────────────────────────────────────────────────────────────
-- D. VÉRIFICATION
-- ────────────────────────────────────────────────────────────

SELECT
  POLICY_NAME,
  REF_DATABASE_NAME AS DB_CIBLE,
  REF_SCHEMA_NAME AS SCHEMA_CIBLE,
  REF_ENTITY_NAME AS TABLE_CIBLE,
  REF_COLUMN_NAME AS COLONNE
FROM TABLE(VOLTAIRE_GOVERNANCE.INFORMATION_SCHEMA.POLICY_REFERENCES(
  REF_ENTITY_DOMAIN => 'ACCOUNT'
))
WHERE POLICY_KIND = 'PROJECTION_POLICY'
ORDER BY DB_CIBLE, TABLE_CIBLE, COLONNE;
