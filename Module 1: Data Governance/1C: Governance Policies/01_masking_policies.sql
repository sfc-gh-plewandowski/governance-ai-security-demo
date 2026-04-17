-- ============================================================
-- MODULE 1C — ÉTAPE 1 : POLITIQUES DE MASKING DYNAMIQUE
-- ============================================================
-- On crée les politiques de masking AVANT de les attacher.
-- Chaque politique implémente des niveaux d'accès différents
-- selon le rôle actif dans la session (IS_ROLE_IN_SESSION).
--
-- Pré-requis : Modules 1A + 1B exécutés (bases, données, rôles RBAC)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. POLITIQUE : TEXTE PII GÉNÉRIQUE
-- ────────────────────────────────────────────────────────────
-- Utilisée pour : NIR, passeports, permis de conduire, SIRET
-- Tiers : accès complet → hash (pour jointures) → masqué total

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_PII_STRING
AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN SHA2(val)
    ELSE '***MASQUÉ***'
  END;

-- ────────────────────────────────────────────────────────────
-- B. POLITIQUE : ADRESSES EMAIL
-- ────────────────────────────────────────────────────────────
-- Tiers : complet → partiel (domaine visible) → masqué total
-- Le domaine reste visible pour les analystes (utile pour le tri)

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_EMAIL
AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      REGEXP_REPLACE(val, '.+@', '****@')
    ELSE '***MASQUÉ***'
  END;

-- ────────────────────────────────────────────────────────────
-- C. POLITIQUE : NUMÉROS DE TÉLÉPHONE
-- ────────────────────────────────────────────────────────────
-- Tiers : complet → 4 derniers chiffres → masqué total
-- Pattern FR : +33 6 12 34 56 78 → +33 6 ** ** 56 78

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_TELEPHONE
AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      CONCAT(LEFT(val, 6), ' ** ** ', RIGHT(val, 5))
    ELSE '***MASQUÉ***'
  END;

-- ────────────────────────────────────────────────────────────
-- D. POLITIQUE : MONTANTS FINANCIERS
-- ────────────────────────────────────────────────────────────
-- Tiers : montant exact → tranche (arrondi à 10K) → NULL
-- L'analyste voit la tranche pour le reporting, pas le montant exact

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_MONTANT
AS (val NUMBER(12,2))
RETURNS NUMBER(12,2) ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      ROUND(val, -4)
    ELSE NULL
  END;

-- ────────────────────────────────────────────────────────────
-- E. POLITIQUE : SALAIRES (NUMBER 10,2)
-- ────────────────────────────────────────────────────────────
-- Tiers : montant exact → plafonné à 100K → NULL

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_SALAIRE
AS (val NUMBER(10,2))
RETURNS NUMBER(10,2) ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      CASE WHEN val > 100000 THEN 100000.00 ELSE val END
    ELSE NULL
  END;

-- ────────────────────────────────────────────────────────────
-- F. POLITIQUE : DATES (date de naissance, etc.)
-- ────────────────────────────────────────────────────────────
-- Tiers : date exacte → année seulement → NULL

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_DATE_SENSIBLE
AS (val DATE)
RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      DATE_TRUNC('year', val)
    ELSE NULL
  END;

-- ────────────────────────────────────────────────────────────
-- G. POLITIQUE : IBAN
-- ────────────────────────────────────────────────────────────
-- Tiers : complet → pays + 4 derniers → masqué total

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_IBAN
AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      CONCAT(LEFT(val, 4), '****', RIGHT(val, 4))
    ELSE '***MASQUÉ***'
  END;

-- ────────────────────────────────────────────────────────────
-- H. VÉRIFICATION
-- ────────────────────────────────────────────────────────────

SHOW MASKING POLICIES IN SCHEMA VOLTAIRE_GOVERNANCE.POLICIES;
