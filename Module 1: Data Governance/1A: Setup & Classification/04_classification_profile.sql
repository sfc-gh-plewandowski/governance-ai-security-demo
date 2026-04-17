-- ============================================================
-- MODULE 1A — ÉTAPE 4 : CUSTOM CLASSIFIERS & PROFIL
-- ============================================================
-- On a vu dans l'étape 3 que SYSTEM$CLASSIFY ne détecte que
-- ~3 colonnes sur 23. Pour les données françaises, on crée
-- des CUSTOM CLASSIFIERS avec des regex adaptées aux formats
-- FR (NIR, IBAN, téléphone +33).
--
-- Résultat attendu : passage de 3 → 7 détections automatiques !
--
-- Classe : SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
-- Classe : SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
-- Édition requise : Enterprise ou supérieure
--
-- Pré-requis : 01 + 02 + 03 exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- PARTIE A : CUSTOM CLASSIFIERS POUR DONNÉES FRANÇAISES
-- ════════════════════════════════════════════════════════════

-- 1. Classifier : NIR (numéro de Sécurité Sociale française)
--    Format : 15 chiffres (1 sexe + 2 année + 2 mois + 5 lieu + 3 ordre + 2 clé)
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR();

CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR!ADD_REGEX(
    SEMANTIC_CATEGORY => 'FR_NIR',
    PRIVACY_CATEGORY => 'IDENTIFIER',
    VALUE_REGEX => '^[12][0-9]{14}$',
    COL_NAME_REGEX => '.*NIR.*|.*SECU.*|.*SSN.*',
    DESCRIPTION => 'Numéro de Sécurité Sociale française (NIR) — 15 chiffres'
);

-- 2. Classifier : IBAN français
--    Format : FR suivi de 25 chiffres (27 caractères total)
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN();

CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN!ADD_REGEX(
    SEMANTIC_CATEGORY => 'FR_IBAN',
    PRIVACY_CATEGORY => 'IDENTIFIER',
    VALUE_REGEX => '^FR[0-9]{25}$',
    COL_NAME_REGEX => '.*IBAN.*',
    DESCRIPTION => 'IBAN français — FR + 25 chiffres'
);

-- 3. Classifier : Téléphone français
--    Format : +33 X XX XX XX XX (avec espaces)
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE();

CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE!ADD_REGEX(
    SEMANTIC_CATEGORY => 'FR_PHONE',
    PRIVACY_CATEGORY => 'IDENTIFIER',
    VALUE_REGEX => '^\\+33 [1-9] [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$',
    COL_NAME_REGEX => '.*TEL.*',
    DESCRIPTION => 'Téléphone français +33 X XX XX XX XX'
);

-- ════════════════════════════════════════════════════════════
-- PARTIE B : VÉRIFIER LES CLASSIFIERS
-- ════════════════════════════════════════════════════════════

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR!LIST();
SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN!LIST();
SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE!LIST();

-- Test rapide : les regex matchent-elles nos données ?
SELECT 'NIR' AS TEST,
    NIR,
    NIR REGEXP '^[12][0-9]{14}$' AS MATCHES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL LIMIT 3;

SELECT 'IBAN' AS TEST,
    IBAN,
    IBAN REGEXP '^FR[0-9]{25}$' AS MATCHES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL LIMIT 3;

SELECT 'TEL' AS TEST,
    TELEPHONE_PRO,
    TELEPHONE_PRO REGEXP '^\\+33 [1-9] [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$' AS MATCHES
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL LIMIT 3;

-- ════════════════════════════════════════════════════════════
-- PARTIE C : PROFIL BASIQUE (pour comparer)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_BASIQUE(
    {
        'minimum_object_age_for_classification_days': 0,
        'maximum_classification_validity_days': 30,
        'auto_tag': true
    }
);

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_BASIQUE!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE D : PROFIL FRANCE AVEC CUSTOM CLASSIFIERS
-- ════════════════════════════════════════════════════════════

-- Étape 1 : créer le profil avec les catégories FR standard
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_FRANCE(
    {
        'minimum_object_age_for_classification_days': 0,
        'maximum_classification_validity_days': 30,
        'auto_tag': true,
        'classify_views': true,
        'snowflake_semantic_categories': [
            {'category': 'NAME'},
            {'category': 'EMAIL'},
            {'category': 'PHONE_NUMBER'},
            {'category': 'BANK_ACCOUNT'},
            {'category': 'PAYMENT_CARD'},
            {'category': 'DATE_OF_BIRTH'},
            {'category': 'SALARY'},
            {'category': 'GENDER'},
            {'category': 'NATIONAL_IDENTIFIER', 'country_codes': ['FR']},
            {'category': 'PASSPORT', 'country_codes': ['FR']},
            {'category': 'DRIVERS_LICENSE', 'country_codes': ['FR']},
            {'category': 'TAX_IDENTIFIER', 'country_codes': ['FR']}
        ]
    }
);

-- Étape 2 : attacher les custom classifiers au profil
-- (on utilise SET_CUSTOM_CLASSIFIERS car les LIST() ne peuvent
-- pas être intégrés directement dans le JSON de CREATE)
CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_FRANCE!SET_CUSTOM_CLASSIFIERS(
    {
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR!LIST(),
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN!LIST(),
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE!LIST()
    }
);

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_FRANCE!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE E : TESTER — AVANT / APRÈS CUSTOM CLASSIFIERS
-- ════════════════════════════════════════════════════════════

-- AVANT (profil basique, sans custom classifiers) :
CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.PERSONNEL',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_BASIQUE'
);

SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f
WHERE f.VALUE:recommendation:semantic_category IS NOT NULL
ORDER BY NOM_COLONNE;

-- ┌─────────────────────────────────────────────────────────┐
-- │  AVANT : ~3 colonnes (EMAIL_PRO, PASSEPORT, PERMIS)    │
-- └─────────────────────────────────────────────────────────┘

-- APRÈS (profil France, avec custom classifiers) :
CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.PERSONNEL',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_FRANCE'
);

SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE,
    f.VALUE:recommendation:privacy_category::STRING AS VIE_PRIVEE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE,
    f.VALUE:recommendation:coverage::NUMBER AS COUVERTURE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f
WHERE f.VALUE:recommendation:semantic_category IS NOT NULL
ORDER BY NOM_COLONNE;

-- ┌─────────────────────────────────────────────────────────┐
-- │  APRÈS : 7 colonnes détectées !                         │
-- │                                                         │
-- │  ✅ EMAIL_PRO         → EMAIL (natif)                   │
-- │  ✅ IBAN              → FR_IBAN (custom)                │
-- │  ✅ NIR               → FR_NIR (custom)                 │
-- │  ✅ NUMERO_PASSEPORT  → PASSPORT (natif)                │
-- │  ✅ PERMIS_CONDUIRE   → DRIVERS_LICENSE (natif)         │
-- │  ✅ TELEPHONE_PERSO   → FR_PHONE (custom)               │
-- │  ✅ TELEPHONE_PRO     → FR_PHONE (custom)               │
-- │                                                         │
-- │  +4 colonnes grâce aux custom classifiers !             │
-- └─────────────────────────────────────────────────────────┘

-- ════════════════════════════════════════════════════════════
-- PARTIE F : PROFIL PRODUCTION AVEC TAG MAP
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION(
    {
        'minimum_object_age_for_classification_days': 0,
        'maximum_classification_validity_days': 30,
        'auto_tag': true,
        'classify_views': true,
        'snowflake_semantic_categories': [
            {'category': 'NAME'},
            {'category': 'EMAIL'},
            {'category': 'PHONE_NUMBER'},
            {'category': 'BANK_ACCOUNT'},
            {'category': 'PAYMENT_CARD'},
            {'category': 'DATE_OF_BIRTH'},
            {'category': 'SALARY'},
            {'category': 'GENDER'},
            {'category': 'NATIONAL_IDENTIFIER', 'country_codes': ['FR']},
            {'category': 'PASSPORT', 'country_codes': ['FR']},
            {'category': 'DRIVERS_LICENSE', 'country_codes': ['FR']},
            {'category': 'TAX_IDENTIFIER', 'country_codes': ['FR']}
        ],
        'tag_map': {
            'column_tag_map': [
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE',
                    'tag_value': 'TRES_SENSIBLE',
                    'semantic_categories': ['NAME', 'NATIONAL_IDENTIFIER', 'PASSPORT', 'BANK_ACCOUNT', 'PAYMENT_CARD', 'FR_NIR', 'FR_IBAN']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE',
                    'tag_value': 'SENSIBLE',
                    'semantic_categories': ['EMAIL', 'PHONE_NUMBER', 'DRIVERS_LICENSE', 'TAX_IDENTIFIER', 'DATE_OF_BIRTH', 'FR_PHONE']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE',
                    'tag_value': 'INTERNE',
                    'semantic_categories': ['SALARY', 'GENDER']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.RGPD',
                    'tag_value': 'IDENTIFIANT_DIRECT',
                    'semantic_categories': ['NAME', 'EMAIL', 'NATIONAL_IDENTIFIER', 'PASSPORT', 'BANK_ACCOUNT', 'PAYMENT_CARD', 'FR_NIR', 'FR_IBAN']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.RGPD',
                    'tag_value': 'QUASI_IDENTIFIANT',
                    'semantic_categories': ['PHONE_NUMBER', 'DATE_OF_BIRTH', 'DRIVERS_LICENSE', 'TAX_IDENTIFIER', 'FR_PHONE']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.RGPD',
                    'tag_value': 'DONNEE_SENSIBLE',
                    'semantic_categories': ['SALARY']
                }
            ]
        }
    }
);

-- Attacher les custom classifiers au profil de production aussi :
CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!SET_CUSTOM_CLASSIFIERS(
    {
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_NIR!LIST(),
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_IBAN!LIST(),
        'VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE': VOLTAIRE_GOVERNANCE.CLASSIFICATION.FR_TELEPHONE!LIST()
    }
);

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE G : VÉRIFIER LES TAGS PRODUITS PAR LE PROFIL
-- ════════════════════════════════════════════════════════════

-- Tester le profil production sur PERSONNEL.
-- Le profil porte auto_tag: true, donc les tags sont appliqués automatiquement :
CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.PERSONNEL',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION'
);

-- Vérifier les tags métier appliqués :
SELECT
    COLUMN_NAME,
    TAG_NAME,
    TAG_VALUE
FROM TABLE(
    VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'VOLTAIRE_RH.EMPLOYES.PERSONNEL', 'TABLE'
    )
)
WHERE TAG_NAME IN ('SENSIBILITE', 'RGPD', 'SEMANTIC_CATEGORY', 'PRIVACY_CATEGORY')
ORDER BY COLUMN_NAME, TAG_NAME;

-- ════════════════════════════════════════════════════════════
-- PARTIE H : PRIVILÈGES EN PRODUCTION
-- ════════════════════════════════════════════════════════════

CREATE ROLE IF NOT EXISTS CLASSIFICATION_ENGINEER;
GRANT ROLE CLASSIFICATION_ENGINEER TO ROLE SYSADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CLASSIFICATION_ADMIN TO ROLE CLASSIFICATION_ENGINEER;

GRANT CREATE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    ON SCHEMA VOLTAIRE_GOVERNANCE.CLASSIFICATION
    TO ROLE CLASSIFICATION_ENGINEER;

GRANT CREATE SNOWFLAKE.DATA_PRIVACY.CUSTOM_CLASSIFIER
    ON SCHEMA VOLTAIRE_GOVERNANCE.CLASSIFICATION
    TO ROLE CLASSIFICATION_ENGINEER;

GRANT USAGE ON DATABASE VOLTAIRE_GOVERNANCE TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON SCHEMA VOLTAIRE_GOVERNANCE.CLASSIFICATION TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON DATABASE VOLTAIRE_CRM TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON DATABASE VOLTAIRE_RH TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON DATABASE VOLTAIRE_FINANCE TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON DATABASE VOLTAIRE_DATALAKE TO ROLE CLASSIFICATION_ENGINEER;

GRANT EXECUTE AUTO CLASSIFICATION ON DATABASE VOLTAIRE_CRM TO ROLE CLASSIFICATION_ENGINEER;
GRANT EXECUTE AUTO CLASSIFICATION ON DATABASE VOLTAIRE_RH TO ROLE CLASSIFICATION_ENGINEER;
GRANT EXECUTE AUTO CLASSIFICATION ON DATABASE VOLTAIRE_FINANCE TO ROLE CLASSIFICATION_ENGINEER;
GRANT EXECUTE AUTO CLASSIFICATION ON DATABASE VOLTAIRE_DATALAKE TO ROLE CLASSIFICATION_ENGINEER;

GRANT APPLY TAG ON ACCOUNT TO ROLE CLASSIFICATION_ENGINEER;
GRANT USAGE ON WAREHOUSE WORKSHOP_WH TO ROLE CLASSIFICATION_ENGINEER;

-- ════════════════════════════════════════════════════════════
-- PARTIE I : CLASSIFIER TOUTES LES TABLES AVEC LE PROFIL
-- ════════════════════════════════════════════════════════════

-- ⚠️  WORKSHOP ONLY — en production, on ne fait PAS ça table par table.
-- En production : ALTER DATABASE ... SET CLASSIFICATION_PROFILE (script 05)
-- et Snowflake classifie tout automatiquement (~22K tables/jour).
--
-- Ici on appelle SYSTEM$CLASSIFY manuellement parce que l'auto-classification
-- a un délai d'~1h après l'activation du profil. On ne peut pas attendre
-- pendant le workshop, donc on force la classification pour voir les
-- résultats immédiatement.
--
-- SYSTEM$CLASSIFY n'existe qu'au niveau TABLE — il n'y a pas de
-- SYSTEM$CLASSIFY('DATABASE'). Pour l'échelle, c'est le profil attaché
-- à la base qui fait le travail.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CONTACTS.PERSONNES',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CLIENTS.ENTREPRISES',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.PAIE.BULLETINS',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.RECRUTEMENT.CANDIDATS',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');
CALL SYSTEM$CLASSIFY('VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION');

-- ════════════════════════════════════════════════════════════
-- PARTIE J : BILAN FINAL CROSS-DATABASE
-- ════════════════════════════════════════════════════════════

SELECT TABLE_NAME, COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM (
    SELECT 'VOLTAIRE_RH.EMPLOYES.PERSONNEL' AS TABLE_NAME, COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.EMPLOYES.PERSONNEL','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_CRM.CONTACTS.PERSONNES', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CONTACTS.PERSONNES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_CRM.CLIENTS.ENTREPRISES', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CLIENTS.ENTREPRISES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_RH.PAIE.BULLETINS', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.PAIE.BULLETINS','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_RH.RECRUTEMENT.CANDIDATS', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.RECRUTEMENT.CANDIDATS','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS', COLUMN_NAME, TAG_NAME, TAG_VALUE
    FROM TABLE(VOLTAIRE_DATALAKE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS','TABLE'))
)
WHERE TAG_NAME IN ('SENSIBILITE', 'RGPD', 'SEMANTIC_CATEGORY')
ORDER BY TABLE_NAME, COLUMN_NAME, TAG_NAME;

-- ════════════════════════════════════════════════════════════
-- PARTIE K : ACTIVER L'AUTO-CLASSIFICATION SUR LES BASES
-- ════════════════════════════════════════════════════════════

-- En production, c'est ÇA le vrai geste : attacher le profil aux bases.
-- À partir de ce moment, Snowflake classifie automatiquement toutes les
-- tables existantes ET futures (~22K tables/jour, délai initial ~1h).

ALTER DATABASE VOLTAIRE_CRM
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_RH
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_FINANCE
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_DATALAKE
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

-- Vérifier que les profils sont bien activés :
-- (SHOW PARAMETERS ne fonctionne PAS pour les classification profiles —
--  il faut utiliser SYSTEM$SHOW_SENSITIVE_DATA_MONITORED_ENTITIES)
SELECT PARSE_JSON(SYSTEM$SHOW_SENSITIVE_DATA_MONITORED_ENTITIES('DATABASE')) AS BASES_SURVEILLEES;

-- ════════════════════════════════════════════════════════════
-- NETTOYAGE (optionnel, si vous voulez repartir de zéro)
-- ════════════════════════════════════════════════════════════

-- ALTER DATABASE VOLTAIRE_CRM UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_RH UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_FINANCE UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_DATALAKE UNSET CLASSIFICATION_PROFILE;
-- DROP SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE IF EXISTS
--     VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION;
