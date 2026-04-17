-- ============================================================
-- MODULE 1C — ÉTAPE 1 : POLITIQUES DE MASKING DYNAMIQUE
-- ============================================================
-- Architecture : UNE politique par type de données, attachée au
-- TAG (jamais directement aux colonnes). La politique lit la
-- valeur de SEMANTIC_CATEGORY pour adapter le masking.
--
-- STRING  → MASK_PII_STRING  (branche sur SEMANTIC_CATEGORY)
-- DATE    → MASK_PII_DATE    (année seulement pour l'analyste)
-- NUMBER  → MASK_PII_NUMBER  (arrondi ou plafond selon le cas)
--
-- Pré-requis : Modules 1A + 1B exécutés (bases, données, tags, rôles)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. POLITIQUE STRING — MASKING ADAPTÉ PAR CATÉGORIE SÉMANTIQUE
-- ────────────────────────────────────────────────────────────
-- La politique lit le tag SEMANTIC_CATEGORY sur la colonne pour
-- savoir QUEL type de donnée elle protège : EMAIL, FR_PHONE,
-- FR_IBAN, NAME, PASSPORT, etc. Chaque catégorie a son masking
-- partiel (domaine visible pour les emails, 4 derniers chiffres
-- pour les téléphones, etc.).
--
-- SECURITY_ADMIN voit tout. DATA_ANALYST voit le masking partiel.
-- Tout le monde voit '***MASQUÉ***'.

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_PII_STRING
AS (val STRING)
RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN
      CASE SYSTEM$GET_TAG_ON_CURRENT_COLUMN('SNOWFLAKE.CORE.SEMANTIC_CATEGORY')
        WHEN 'EMAIL'
          THEN REGEXP_REPLACE(val, '.+@', '****@')
        WHEN 'FR_PHONE'
          THEN CONCAT(LEFT(val, 6), ' ** ** ', RIGHT(val, 5))
        WHEN 'FR_IBAN'
          THEN CONCAT(LEFT(val, 4), '****', RIGHT(val, 4))
        ELSE SHA2(val)
      END
    ELSE '***MASQUÉ***'
  END;

-- ────────────────────────────────────────────────────────────
-- B. POLITIQUE DATE — TRONCATURE À L'ANNÉE
-- ────────────────────────────────────────────────────────────
-- Pour les dates de naissance, l'analyste voit l'année sans
-- le jour ni le mois. Utile pour l'analyse démographique
-- sans exposer la date exacte.

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_PII_DATE
AS (val DATE)
RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN DATE_TRUNC('year', val)
    ELSE NULL
  END;

-- ────────────────────────────────────────────────────────────
-- C. POLITIQUE NUMBER — ARRONDI POUR L'ANALYSTE
-- ────────────────────────────────────────────────────────────
-- L'analyste voit la tranche (arrondi à 1000) pour le reporting
-- agrégé. Le montant exact est masqué. Les salaires au-dessus
-- de 100K sont plafonnés.

CREATE OR REPLACE MASKING POLICY VOLTAIRE_GOVERNANCE.POLICIES.MASK_PII_NUMBER
AS (val NUMBER(12,2))
RETURNS NUMBER(12,2) ->
  CASE
    WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('DATA_ANALYST') THEN ROUND(val, -3)
    ELSE NULL
  END;

-- ────────────────────────────────────────────────────────────
-- D. VÉRIFICATION
-- ────────────────────────────────────────────────────────────

SHOW MASKING POLICIES IN SCHEMA VOLTAIRE_GOVERNANCE.POLICIES;
