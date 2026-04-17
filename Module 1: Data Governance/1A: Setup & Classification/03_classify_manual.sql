-- ============================================================
-- MODULE 1A — ÉTAPE 3 : DÉCOUVERTE — SYSTEM$CLASSIFY
-- ============================================================
-- Première rencontre avec SYSTEM$CLASSIFY : on lance la
-- classification automatique sur une table et on découvre
-- les limites de la détection native sur données françaises.
--
-- C'est le moment-clé : Snowflake détecte bien les patterns
-- universels (email, passeport), mais les formats spécifiques
-- français (NIR, IBAN FR, +33) passent à travers.
--
-- → D'où la nécessité des CUSTOM CLASSIFIERS (étape 04).
--
-- Pré-requis : 01 + 02 exécutés (tables chargées)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- PARTIE A : CLASSIFICATION AUTOMATIQUE — DRY RUN
-- ════════════════════════════════════════════════════════════

-- Classifier la table EMPLOYES sans appliquer de tags.
-- Le deuxième paramètre NULL = juste observer, ne rien toucher.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', null);

-- Parser le résultat JSON :
SELECT
    f.KEY AS NOM_COLONNE,
    f.VALUE:recommendation:semantic_category::STRING AS CATEGORIE_SEMANTIQUE,
    f.VALUE:recommendation:privacy_category::STRING AS CATEGORIE_VIE_PRIVEE,
    f.VALUE:recommendation:confidence::STRING AS CONFIANCE,
    f.VALUE:recommendation:coverage::NUMBER AS COUVERTURE
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
     TABLE(FLATTEN(INPUT => r.$1:classification_result)) f
ORDER BY CATEGORIE_SEMANTIQUE NULLS LAST;

-- ┌─────────────────────────────────────────────────────────┐
-- │  RÉSULTAT ATTENDU : seulement ~3 colonnes détectées !   │
-- │                                                         │
-- │  ✅ EMAIL_PRO         → EMAIL / IDENTIFIER / HIGH       │
-- │  ✅ NUMERO_PASSEPORT  → PASSPORT / IDENTIFIER / HIGH    │
-- │  ✅ PERMIS_CONDUIRE   → DRIVERS_LICENSE / IDENTIFIER    │
-- │                                                         │
-- │  ❌ NOM, PRENOM       → non détectés (noms français)    │
-- │  ❌ TELEPHONE_*       → non détectés (+33 format)       │
-- │  ❌ NIR               → non détecté (sécu française)    │
-- │  ❌ IBAN              → non détecté (FR76...)           │
-- │  ❌ ADRESSE, VILLE    → non détectés                    │
-- │  ❌ DATE_NAISSANCE    → non détecté                     │
-- │                                                         │
-- │  3 sur 23 = 13% de couverture.                          │
-- │  En production française, c'est insuffisant.            │
-- │                                                         │
-- │  → Solution : CUSTOM CLASSIFIERS (étape 04)             │
-- └─────────────────────────────────────────────────────────┘

-- ════════════════════════════════════════════════════════════
-- PARTIE B : COMPRENDRE POURQUOI
-- ════════════════════════════════════════════════════════════

-- Regardons les données que Snowflake n'a pas reconnues :
SELECT
    NIR,              -- 15 chiffres (format sécu FR)
    IBAN,             -- FR76 + 23 chiffres
    TELEPHONE_PRO,    -- +33 X XX XX XX XX
    NOM,              -- Noms français
    ADRESSE           -- Adresses FR
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL LIMIT 5;

-- SYSTEM$CLASSIFY utilise des heuristiques (regex internes + ML)
-- entraînées principalement sur des données anglophones :
--   • SSN américain (XXX-XX-XXXX) → reconnu
--   • NIR français (15 chiffres consécutifs) → pas reconnu
--   • US phone (XXX-XXX-XXXX) → reconnu
--   • FR phone (+33 X XX XX XX XX) → pas reconnu
--   • IBAN (FR76...) → pas reconnu

-- ════════════════════════════════════════════════════════════
-- PARTIE C : CLASSIFIER LES AUTRES TABLES (même constat)
-- ════════════════════════════════════════════════════════════

-- Lançons sur toutes les tables pour avoir le panorama complet.
-- auto_tag = true → Snowflake pose les system tags sur ce qu'il détecte.
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.EMPLOYES.PERSONNEL', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CONTACTS.PERSONNES', {'auto_tag': true, 'sample_count': 5000});
CALL SYSTEM$CLASSIFY('VOLTAIRE_CRM.CLIENTS.ENTREPRISES', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.PAIE.BULLETINS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_RH.RECRUTEMENT.CANDIDATS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS', {'auto_tag': true});
CALL SYSTEM$CLASSIFY('VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS', {'auto_tag': true});

-- ════════════════════════════════════════════════════════════
-- PARTIE D : BILAN — QU'EST-CE QUI A ÉTÉ DÉTECTÉ ?
-- ════════════════════════════════════════════════════════════

SELECT 'VOLTAIRE_RH.EMPLOYES.PERSONNEL' AS TABLE_NAME, COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.EMPLOYES.PERSONNEL','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_CRM.CONTACTS.PERSONNES', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CONTACTS.PERSONNES','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_CRM.CLIENTS.ENTREPRISES', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_CRM.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_CRM.CLIENTS.ENTREPRISES','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_RH.PAIE.BULLETINS', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.PAIE.BULLETINS','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_RH.RECRUTEMENT.CANDIDATS', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_RH.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_RH.RECRUTEMENT.CANDIDATS','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_FINANCE.COMPTABILITE.FACTURES', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.COMPTABILITE.FACTURES','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
UNION ALL
SELECT 'VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS', COLUMN_NAME, TAG_NAME, TAG_VALUE
FROM TABLE(VOLTAIRE_DATALAKE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS','TABLE'))
WHERE TAG_NAME = 'SEMANTIC_CATEGORY'
ORDER BY TABLE_NAME, COLUMN_NAME;

-- ┌──────────────────────────────────────────────────────────┐
-- │  CONSTAT : Snowflake détecte les emails et passeports    │
-- │  sur toutes les tables, mais rate systématiquement :     │
-- │    • Les téléphones français (+33)                       │
-- │    • Les NIR / numéros de sécu                           │
-- │    • Les IBAN français                                   │
-- │    • Les noms/prénoms/adresses françaises                │
-- │                                                         │
-- │  → Étape 04 : on crée des CUSTOM CLASSIFIERS pour       │
-- │    combler ces lacunes avec des regex françaises.        │
-- └──────────────────────────────────────────────────────────┘
