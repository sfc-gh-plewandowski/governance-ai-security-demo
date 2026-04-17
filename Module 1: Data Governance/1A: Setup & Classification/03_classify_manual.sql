-- ============================================================
-- MODULE 1A — ÉTAPE 3 : CLASSIFICATION MANUELLE
-- ============================================================
-- Première rencontre avec SYSTEM$CLASSIFY : on lance la
-- classification sur une table, on inspecte les résultats,
-- on comprend ce que Snowflake détecte automatiquement.
--
-- Pré-requis : 01 + 02 exécutés (tables chargées)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- PARTIE A : CLASSIFICATION SIMPLE (une table, pas de tags)
-- ════════════════════════════════════════════════════════════

-- Classifier la table EMPLOYES sans appliquer de tags (mode "dry run").
-- On veut juste voir ce que Snowflake détecte.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', null);

-- Le résultat est un JSON. Pour le lire plus facilement,
-- on utilise RESULT_SCAN pour récupérer la sortie du CALL précédent :
SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE_SEMANTIQUE,
    f.VALUE:recommendation:privacy_category::STRING AS CATEGORIE_VIE_PRIVEE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE,
    f.VALUE:recommendation:coverage::NUMBER AS COUVERTURE,
    f.VALUE:valid_value_ratio::NUMBER AS RATIO_VALEURS_VALIDES
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f;

-- ════════════════════════════════════════════════════════════
-- PARTIE B : CLASSIFICATION AVEC AUTO_TAG
-- ════════════════════════════════════════════════════════════

-- Maintenant on applique les tags automatiquement.
-- Snowflake va poser les system tags SEMANTIC_CATEGORY et PRIVACY_CATEGORY
-- directement sur les colonnes.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', {'auto_tag': true});

-- Vérifier les tags appliqués :
SELECT
    TAG_NAME,
    TAG_SCHEMA,
    COLUMN_NAME,
    TAG_VALUE
FROM TABLE(
    VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'VOLTAIRE_RH.EMPLOYES.PERSONNEL', 'TABLE'
    )
)
ORDER BY COLUMN_NAME, TAG_NAME;

-- ════════════════════════════════════════════════════════════
-- PARTIE C : CLASSIFICATION AVEC PLUS D'ÉCHANTILLONS
-- ════════════════════════════════════════════════════════════

-- Sur des grosses tables, on peut augmenter l'échantillonnage (max 10 000).
-- Plus de lignes = meilleure confiance, mais plus lent.
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CONTACTS.PERSONNES',
    {'sample_count': 5000, 'auto_tag': true});

-- Vérifier :
SELECT
    TAG_NAME,
    COLUMN_NAME,
    TAG_VALUE
FROM TABLE(
    VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'VOLTAIRE_CRM.CONTACTS.PERSONNES', 'TABLE'
    )
)
ORDER BY COLUMN_NAME, TAG_NAME;

-- ════════════════════════════════════════════════════════════
-- PARTIE D : CLASSIFIER PLUSIEURS TABLES D'UN COUP
-- ════════════════════════════════════════════════════════════

-- Table par table (utile pour contrôle fin) :
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CLIENTS.ENTREPRISES', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.PAIE.BULLETINS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.RECRUTEMENT.CANDIDATS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS', {'auto_tag': true});

-- ════════════════════════════════════════════════════════════
-- PARTIE E : INSPECTER LES RÉSULTATS DÉTAILLÉS
-- ════════════════════════════════════════════════════════════

-- Vue d'ensemble : quels types de PII ont été trouvés dans EMPLOYES ?
-- D'abord on appelle CLASSIFY, puis on parse avec RESULT_SCAN.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', null);

SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE,
    f.VALUE:recommendation:privacy_category::STRING AS VIE_PRIVEE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE,
    ARRAY_SIZE(f.VALUE:recommendation:details) AS NB_DETAILS,
    CASE
        WHEN ARRAY_SIZE(f.VALUE:recommendation:details) > 0
        THEN f.VALUE:recommendation:details[0]:semantic_category::STRING
        ELSE NULL
    END AS SOUS_CATEGORIE_PAYS,
    f.VALUE:recommendation:coverage::NUMBER AS COUVERTURE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f
ORDER BY VIE_PRIVEE, CATEGORIE;

-- Détail des sous-catégories françaises (FR_SSN, FR_PASSPORT, etc.)
-- Les "details" contiennent les subcategories spécifiques au pays.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', null);

SELECT
    f.KEY AS NOM_COLONNE,
    d.VALUE:semantic_category::STRING AS SOUS_CATEGORIE,
    d.VALUE:coverage::NUMBER AS COUVERTURE_PAYS
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f,
     TABLE(FLATTEN(INPUT => f.VALUE:recommendation:details, OUTER => TRUE)) d
WHERE d.VALUE:semantic_category IS NOT NULL
ORDER BY NOM_COLONNE;

-- ════════════════════════════════════════════════════════════
-- PARTIE F : RÉSUMÉ CROSS-DATABASE
-- ════════════════════════════════════════════════════════════

-- Combien de colonnes taggées par base ?
-- Alternative immédiate avec INFORMATION_SCHEMA par table :

SELECT 'VOLTAIRE_RH.EMPLOYES.PERSONNEL' AS TABLE_NAME, TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.EMPLOYES.PERSONNEL','TABLE'))
UNION ALL
SELECT 'VOLTAIRE_CRM.CONTACTS.PERSONNES', TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CONTACTS.PERSONNES','TABLE'))
UNION ALL
SELECT 'VOLTAIRE_CRM.CLIENTS.ENTREPRISES', TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CLIENTS.ENTREPRISES','TABLE'))
UNION ALL
SELECT 'VOLTAIRE_RH.PAIE.BULLETINS', TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.PAIE.BULLETINS','TABLE'))
UNION ALL
SELECT 'VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', TAG_NAME, TAG_VALUE, COLUMN_NAME
FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES','TABLE'))
ORDER BY TABLE_NAME, COLUMN_NAME, TAG_NAME;
