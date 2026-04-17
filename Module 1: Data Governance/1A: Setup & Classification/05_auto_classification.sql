-- ============================================================
-- MODULE 1A — ÉTAPE 5 : CLASSIFICATION AUTOMATIQUE
-- ============================================================
-- Maintenant qu'on a testé le profil, on l'active sur les bases.
-- Snowflake classifiera automatiquement :
--   • Les tables existantes (après ~1h de délai)
--   • Les nouvelles tables dès qu'elles sont créées
--
-- C'est la vraie puissance : classification continue, sans
-- intervention manuelle, sur tout le cycle de vie des données.
--
-- Pré-requis : 01 + 02 + 03 + 04 exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- PARTIE A : ACTIVER LE PROFIL SUR LES BASES
-- ════════════════════════════════════════════════════════════

-- Attacher le profil de production à chaque base de données.
-- Toutes les tables dans ces bases seront automatiquement
-- classifiées et taggées selon les règles du profil.

ALTER DATABASE VOLTAIRE_CRM
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_RH
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_FINANCE
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

ALTER DATABASE VOLTAIRE_DATALAKE
    SET CLASSIFICATION_PROFILE = 'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION';

-- Vérifier que le profil est bien activé :
SHOW PARAMETERS LIKE 'CLASSIFICATION_PROFILE' IN DATABASE VOLTAIRE_RH;

-- ════════════════════════════════════════════════════════════
-- PARTIE B : COMPRENDRE LE DÉLAI
-- ════════════════════════════════════════════════════════════

-- IMPORTANT : Il y a un délai d'environ 1 heure entre le moment
-- où on attache le profil et le moment où Snowflake commence
-- à classifier automatiquement.
--
-- Pour le workshop, on ne peut pas attendre 1h. Donc :
--   1. On a déjà classifié manuellement dans 03_classify_manual.sql
--   2. On a testé le profil dans 04_classification_profile.sql
--   3. Ici on MONTRE comment ça fonctionne en production
--   4. On simule l'auto-classification avec SYSTEM$CLASSIFY + profil
--
-- En production réelle :
--   • Jour 1 : créer le profil, l'attacher aux bases
--   • Jour 2 : vérifier les résultats avec SYSTEM$GET_CLASSIFICATION_RESULT
--   • Continu : chaque nouvelle table est classifiée automatiquement

-- ════════════════════════════════════════════════════════════
-- PARTIE C : SIMULER L'AUTO-CLASSIFICATION (NOUVELLE TABLE)
-- ════════════════════════════════════════════════════════════

-- Scénario : un Data Engineer crée une nouvelle table avec des
-- données sensibles. Le profil la classifiera automatiquement.
-- On simule en créant la table + lançant CLASSIFY avec le profil.

CREATE OR REPLACE TABLE VOLTAIRE_RH.EMPLOYES.STAGIAIRES (
    STAGIAIRE_ID        NUMBER AUTOINCREMENT,
    PRENOM              STRING,
    NOM                 STRING,
    EMAIL_PERSO         STRING,
    TELEPHONE           STRING,
    DATE_NAISSANCE      DATE,
    NIR                 STRING,
    ECOLE               STRING,
    TUTEUR_ID           NUMBER,
    DATE_DEBUT          DATE,
    DATE_FIN            DATE,
    GRATIFICATION       NUMBER(10,2)
);

INSERT INTO VOLTAIRE_RH.EMPLOYES.STAGIAIRES
    (PRENOM, NOM, EMAIL_PERSO, TELEPHONE, DATE_NAISSANCE, NIR, ECOLE, TUTEUR_ID, DATE_DEBUT, DATE_FIN, GRATIFICATION)
SELECT
    PRENOM,
    NOM,
    REPLACE(EMAIL_PRO, '@voltaire-analytics.fr', '@' ||
        CASE MOD(EMPLOYE_ID, 5)
            WHEN 0 THEN 'gmail.com'
            WHEN 1 THEN 'outlook.fr'
            WHEN 2 THEN 'yahoo.fr'
            WHEN 3 THEN 'hotmail.fr'
            ELSE 'protonmail.com'
        END
    ),
    TELEPHONE_PERSO,
    DATE_NAISSANCE,
    NIR,
    CASE MOD(EMPLOYE_ID, 8)
        WHEN 0 THEN 'École Polytechnique'
        WHEN 1 THEN 'HEC Paris'
        WHEN 2 THEN 'ESSEC'
        WHEN 3 THEN 'CentraleSupélec'
        WHEN 4 THEN 'Sciences Po Paris'
        WHEN 5 THEN 'INSA Lyon'
        WHEN 6 THEN 'Université Paris-Saclay'
        ELSE 'EPITECH'
    END,
    MOD(EMPLOYE_ID, 50) + 1,
    DATEADD('month', -MOD(EMPLOYE_ID, 6), CURRENT_DATE()),
    DATEADD('month', 6 - MOD(EMPLOYE_ID, 6), CURRENT_DATE()),
    CASE WHEN TYPE_CONTRAT = 'Stage' THEN 700.00 ELSE 1200.00 END
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID <= 200;

-- Classifier cette nouvelle table avec le profil (simule l'auto-classification) :
CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.STAGIAIRES',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION'
);

-- Vérifier que les tags métier ont été appliqués :
SELECT
    TAG_NAME,
    COLUMN_NAME,
    TAG_VALUE
FROM TABLE(
    VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'VOLTAIRE_RH.EMPLOYES.STAGIAIRES', 'TABLE'
    )
)
ORDER BY COLUMN_NAME, TAG_NAME;

-- ════════════════════════════════════════════════════════════
-- PARTIE D : CONSULTER LES RÉSULTATS D'AUTO-CLASSIFICATION
-- ════════════════════════════════════════════════════════════

-- En production (après le délai d'1h), on utilise cette procédure
-- pour voir les résultats de la dernière auto-classification :

-- CALL SYSTEM$GET_CLASSIFICATION_RESULT('VOLTAIRE_RH.EMPLOYES.PERSONNEL');

-- Pour le workshop, on peut lancer manuellement et parser :
CALL SYSTEM$CLASSIFY(
    'VOLTAIRE_RH.EMPLOYES.STAGIAIRES',
    'VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION'
);

SELECT
    f.KEY AS COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE,
    f.VALUE:recommendation:privacy_category::STRING AS PRIVACY,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f
ORDER BY COLONNE;

-- ════════════════════════════════════════════════════════════
-- PARTIE E : VUE D'ENSEMBLE FINALE — TOUTES LES TABLES TAGGÉES
-- ════════════════════════════════════════════════════════════

-- Résumé : pour chaque table, combien de colonnes ont été classifiées
-- et avec quels tags personnalisés ?

WITH tagged_columns AS (
    SELECT 'VOLTAIRE_RH.EMPLOYES.PERSONNEL' AS T, TAG_NAME, TAG_VALUE, COLUMN_NAME
    FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.EMPLOYES.PERSONNEL','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_RH.EMPLOYES.STAGIAIRES', TAG_NAME, TAG_VALUE, COLUMN_NAME
    FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.EMPLOYES.STAGIAIRES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_CRM.CONTACTS.PERSONNES', TAG_NAME, TAG_VALUE, COLUMN_NAME
    FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CONTACTS.PERSONNES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_CRM.CLIENTS.ENTREPRISES', TAG_NAME, TAG_VALUE, COLUMN_NAME
    FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CLIENTS.ENTREPRISES','TABLE'))
    UNION ALL
    SELECT 'VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', TAG_NAME, TAG_VALUE, COLUMN_NAME
    FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES','TABLE'))
)
SELECT
    T AS TABLE_NAME,
    TAG_NAME,
    TAG_VALUE,
    COUNT(DISTINCT COLUMN_NAME) AS NB_COLONNES
FROM tagged_columns
WHERE TAG_NAME IN ('SENSIBILITE', 'RGPD')
GROUP BY T, TAG_NAME, TAG_VALUE
ORDER BY T, TAG_NAME, TAG_VALUE;

-- ════════════════════════════════════════════════════════════
-- PARTIE F : MODIFIER LE PROFIL (méthodes disponibles)
-- ════════════════════════════════════════════════════════════

-- Les profils sont modifiables à chaud via des méthodes :

-- Changer la période de re-classification :
-- CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!SET_MAXIMUM_CLASSIFICATION_VALIDITY_DAYS(15);

-- Activer la classification des vues :
-- CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!SET_CLASSIFY_VIEWS(true);

-- Ajouter des classifiers custom :
-- CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!SET_CUSTOM_CLASSIFIERS(
--     {'mon_classifier': mon_classifier!list()}
-- );

-- Désactiver l'auto-tagging (mode audit seulement) :
-- CALL VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION!SET_AUTO_TAG(false);

-- ════════════════════════════════════════════════════════════
-- NETTOYAGE (optionnel, si vous voulez repartir de zéro)
-- ════════════════════════════════════════════════════════════

-- ALTER DATABASE VOLTAIRE_CRM UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_RH UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_FINANCE UNSET CLASSIFICATION_PROFILE;
-- ALTER DATABASE VOLTAIRE_DATALAKE UNSET CLASSIFICATION_PROFILE;
-- DROP SNOWFLAKE.DATA_PRIVACY.CLASSIFICATION_PROFILE IF EXISTS
--     VOLTAIRE_GOVERNANCE.CLASSIFICATION.PROFIL_PRODUCTION;
