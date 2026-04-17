-- ============================================================
-- MODULE 1A — ÉTAPE 4 : PROFIL DE CLASSIFICATION
-- ============================================================
-- Les Classification Profiles automatisent et personnalisent
-- la classification. Au lieu de lancer SYSTEM$CLASSIFY manuellement
-- table par table, on crée un profil qui décrit COMMENT classifier,
-- et on l'attache à une base ou un schéma.
--
-- Classe : SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
-- Édition requise : Enterprise ou supérieure
--
-- Pré-requis : 01 + 02 + 03 exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- PARTIE A : PRÉPARER LES PRIVILÈGES
-- ════════════════════════════════════════════════════════════

-- Dans un vrai environnement, on ne fait PAS tout en ACCOUNTADMIN.
-- On délègue la classification à un rôle dédié.

CREATE ROLE IF NOT EXISTS CLASSIFICATION_ENGINEER;
GRANT ROLE CLASSIFICATION_ENGINEER TO ROLE SYSADMIN;

GRANT DATABASE ROLE SNOWFLAKE.CLASSIFICATION_ADMIN TO ROLE CLASSIFICATION_ENGINEER;

GRANT CREATE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
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

-- Pour le workshop on reste en ACCOUNTADMIN, mais on sait
-- quels privilèges seraient nécessaires en production.

-- ════════════════════════════════════════════════════════════
-- PARTIE B : PROFIL BASIQUE
-- ════════════════════════════════════════════════════════════

-- Le profil le plus simple : classifier immédiatement, tagger auto.
CREATE OR REPLACE SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE
    VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_BASIQUE(
    {
        'minimum_object_age_for_classification_days': 0,
        'maximum_classification_validity_days': 30,
        'auto_tag': true,
        'classify_views': false
    }
);

-- Inspecter le profil :
SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_BASIQUE!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE C : PROFIL FRANCE — CATÉGORIES SPÉCIFIQUES
-- ════════════════════════════════════════════════════════════

-- On peut restreindre la classification aux catégories pertinentes
-- pour la France. Snowflake supporte country_codes: ['FR'] pour :
--   • NATIONAL_IDENTIFIER → FR_CNI, FR_SSN (numéro INSEE / NIR)
--   • PASSPORT → FR_PASSPORT
--   • DRIVERS_LICENSE → FR_DRIVERS_LICENSE
--   • TAX_IDENTIFIER → FR_TAX_ID_NUMBER (NIF)
--   • Plus les catégories globales : NAME, EMAIL, PHONE_NUMBER, etc.

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

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_FRANCE!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE D : PROFIL AVEC TAG MAP — CLASSIFICATION → TAGS MÉTIER
-- ════════════════════════════════════════════════════════════

-- Le tag_map relie les résultats de classification aux tags
-- personnalisés créés dans 01_account_setup (SENSIBILITE, RGPD).
-- Quand Snowflake trouve un NAME → on pose automatiquement
-- SENSIBILITE = 'TRES_SENSIBLE' et RGPD = 'IDENTIFIANT_DIRECT'.

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
                    'semantic_categories': ['NAME', 'NATIONAL_IDENTIFIER', 'PASSPORT', 'BANK_ACCOUNT', 'PAYMENT_CARD']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE',
                    'tag_value': 'SENSIBLE',
                    'semantic_categories': ['EMAIL', 'PHONE_NUMBER', 'DRIVERS_LICENSE', 'TAX_IDENTIFIER', 'DATE_OF_BIRTH']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE',
                    'tag_value': 'INTERNE',
                    'semantic_categories': ['SALARY', 'GENDER']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.RGPD',
                    'tag_value': 'IDENTIFIANT_DIRECT',
                    'semantic_categories': ['NAME', 'EMAIL', 'NATIONAL_IDENTIFIER', 'PASSPORT', 'BANK_ACCOUNT', 'PAYMENT_CARD']
                },
                {
                    'tag_name': 'VOLTAIRE_GOVERNANCE.TAGS.RGPD',
                    'tag_value': 'QUASI_IDENTIFIANT',
                    'semantic_categories': ['PHONE_NUMBER', 'DATE_OF_BIRTH', 'DRIVERS_LICENSE', 'TAX_IDENTIFIER']
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

SELECT VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!DESCRIBE();

-- ════════════════════════════════════════════════════════════
-- PARTIE E : TESTER LE PROFIL AVANT DE L'ACTIVER
-- ════════════════════════════════════════════════════════════

-- On peut tester un profil sur une table spécifique avec SYSTEM$CLASSIFY.
-- Cela applique la logique du profil (catégories FR, tag_map)
-- sans activer la classification automatique.

CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.PERSONNEL',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION'
);

-- Parser le résultat pour voir les tags métier appliqués :
-- On utilise RESULT_SCAN pour récupérer le JSON du CALL précédent.
SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE,
    t.VALUE:tag_name::STRING AS TAG_APPLIQUE,
    t.VALUE:tag_value::STRING AS VALEUR_TAG,
    t.VALUE:tag_applied::BOOLEAN AS APPLIQUE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f,
     TABLE(FLATTEN(INPUT => f.VALUE:recommendation:tags)) t
ORDER BY NOM_COLONNE, TAG_APPLIQUE;

-- ════════════════════════════════════════════════════════════
-- PARTIE F : VÉRIFIER LES TAGS APPLIQUÉS
-- ════════════════════════════════════════════════════════════

-- Après le test avec SYSTEM$CLASSIFY + profil, les tags devraient
-- inclure nos tags personnalisés SENSIBILITE et RGPD.

SELECT
    TAG_NAME,
    COLUMN_NAME,
    TAG_VALUE
FROM TABLE(
    VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'VOLTAIRE_RH.EMPLOYES.PERSONNEL', 'TABLE'
    )
)
WHERE TAG_NAME IN ('SENSIBILITE', 'RGPD', 'SEMANTIC_CATEGORY', 'PRIVACY_CATEGORY')
ORDER BY COLUMN_NAME, TAG_NAME;
