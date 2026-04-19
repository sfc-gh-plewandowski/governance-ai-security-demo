-- CERT: D2 Data Protection & Governance (30%) + D1 Access Control (22%) — account setup, warehouses, roles
-- ============================================================
-- MODULE 1A — ÉTAPE 1 : CONFIGURATION DU COMPTE
-- ============================================================
-- Simule un environnement de production réaliste :
--   • Entreprise française fictive "Voltaire Analytics"
--   • Plusieurs bases de données (CRM, RH, Finance, Data Lake)
--   • Schémas multiples par base
--   • Tables, vues, UDFs
--   • Données 100% françaises (noms, téléphones, NIR, passeports, permis)
--
-- Pré-requis : compte trial Enterprise Edition, ACCOUNTADMIN
-- ============================================================

USE ROLE ACCOUNTADMIN;

-- ────────────────────────────────────────────────────────────
-- 0. WAREHOUSE
-- ────────────────────────────────────────────────────────────
CREATE WAREHOUSE IF NOT EXISTS WORKSHOP_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- 1. BASE DE DONNÉES : VOLTAIRE_CRM (données clients)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE VOLTAIRE_CRM;

CREATE SCHEMA VOLTAIRE_CRM.CLIENTS;
CREATE SCHEMA VOLTAIRE_CRM.CONTACTS;
CREATE SCHEMA VOLTAIRE_CRM.STAGING;

-- Table principale : clients B2B
CREATE OR REPLACE TABLE VOLTAIRE_CRM.CLIENTS.ENTREPRISES (
    ENTREPRISE_ID       NUMBER AUTOINCREMENT,
    RAISON_SOCIALE      STRING,
    SIRET               STRING,       -- 14 digits, FR business identifier
    SIREN               STRING,       -- 9 digits, FR company identifier
    NUM_TVA             STRING,       -- FR + 2 digits + SIREN
    ADRESSE             STRING,
    CODE_POSTAL         STRING,
    VILLE               STRING,
    PAYS                STRING DEFAULT 'France',
    TELEPHONE           STRING,
    EMAIL_CONTACT       STRING,
    SITE_WEB            STRING,
    SECTEUR_ACTIVITE    STRING,
    CHIFFRE_AFFAIRES    NUMBER(15,2),
    DATE_CREATION       DATE,
    ACTIF               BOOLEAN DEFAULT TRUE
);

-- Table : contacts individuels chez les clients
CREATE OR REPLACE TABLE VOLTAIRE_CRM.CONTACTS.PERSONNES (
    CONTACT_ID          NUMBER AUTOINCREMENT,
    ENTREPRISE_ID       NUMBER,
    PRENOM              STRING,
    NOM                 STRING,
    EMAIL               STRING,
    TELEPHONE_PORTABLE  STRING,       -- +33 6 XX XX XX XX
    TELEPHONE_FIXE      STRING,       -- +33 1 XX XX XX XX
    FONCTION            STRING,
    DATE_NAISSANCE      DATE,
    GENRE               STRING,
    ADRESSE_PERSO       STRING,
    CODE_POSTAL_PERSO   STRING,
    VILLE_PERSO         STRING,
    NATIONALITE         STRING DEFAULT 'Française'
);

-- Staging : données brutes avant nettoyage
CREATE OR REPLACE TABLE VOLTAIRE_CRM.STAGING.RAW_IMPORTS (
    IMPORT_ID           NUMBER AUTOINCREMENT,
    SOURCE              STRING,
    RAW_DATA            VARIANT,
    IMPORTED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ────────────────────────────────────────────────────────────
-- 2. BASE DE DONNÉES : VOLTAIRE_RH (ressources humaines)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE VOLTAIRE_RH;

CREATE SCHEMA VOLTAIRE_RH.EMPLOYES;
CREATE SCHEMA VOLTAIRE_RH.PAIE;
CREATE SCHEMA VOLTAIRE_RH.RECRUTEMENT;

-- Table principale : employés
CREATE OR REPLACE TABLE VOLTAIRE_RH.EMPLOYES.PERSONNEL (
    EMPLOYE_ID          NUMBER AUTOINCREMENT,
    PRENOM              STRING,
    NOM                 STRING,
    EMAIL_PRO           STRING,
    TELEPHONE_PRO       STRING,
    TELEPHONE_PERSO     STRING,
    DATE_NAISSANCE      DATE,
    LIEU_NAISSANCE      STRING,
    GENRE               STRING,
    NATIONALITE         STRING,
    NIR                 STRING,       -- Numéro de Sécurité Sociale (15 digits)
    NUMERO_PASSEPORT    STRING,       -- FR passport: 2 digits + 2 letters + 5 digits
    PERMIS_CONDUIRE     STRING,       -- FR driver's license
    ADRESSE             STRING,
    CODE_POSTAL         STRING,
    VILLE               STRING,
    IBAN                STRING,       -- FR76 + 23 digits
    POSTE               STRING,
    DEPARTEMENT         STRING,
    DATE_EMBAUCHE       DATE,
    TYPE_CONTRAT        STRING,       -- CDI, CDD, Alternance, Stage
    MANAGER_ID          NUMBER,
    ACTIF               BOOLEAN DEFAULT TRUE
);

-- Table : fiches de paie
CREATE OR REPLACE TABLE VOLTAIRE_RH.PAIE.BULLETINS (
    BULLETIN_ID         NUMBER AUTOINCREMENT,
    EMPLOYE_ID          NUMBER,
    MOIS                STRING,       -- '2026-01'
    SALAIRE_BRUT        NUMBER(10,2),
    SALAIRE_NET         NUMBER(10,2),
    COTISATIONS         NUMBER(10,2),
    PRIMES              NUMBER(10,2),
    HEURES_SUPPLEMENTAIRES NUMBER(5,1),
    DATE_VIREMENT       DATE,
    IBAN_VERSEMENT      STRING
);

-- Table : candidats
CREATE OR REPLACE TABLE VOLTAIRE_RH.RECRUTEMENT.CANDIDATS (
    CANDIDAT_ID         NUMBER AUTOINCREMENT,
    PRENOM              STRING,
    NOM                 STRING,
    EMAIL               STRING,
    TELEPHONE           STRING,
    DATE_NAISSANCE      DATE,
    ADRESSE             STRING,
    CODE_POSTAL         STRING,
    VILLE               STRING,
    DIPLOME             STRING,
    ANNEES_EXPERIENCE   NUMBER,
    POSTE_VISE          STRING,
    SALAIRE_SOUHAITE    NUMBER(10,2),
    DATE_CANDIDATURE    DATE,
    STATUT              STRING DEFAULT 'EN_COURS'
);

-- ────────────────────────────────────────────────────────────
-- 3. BASE DE DONNÉES : VOLTAIRE_FINANCE (comptabilité)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE VOLTAIRE_FINANCE;

CREATE SCHEMA VOLTAIRE_FINANCE.COMPTABILITE;
CREATE SCHEMA VOLTAIRE_FINANCE.TRESORERIE;

-- Table : factures
CREATE OR REPLACE TABLE VOLTAIRE_FINANCE.COMPTABILITE.FACTURES (
    FACTURE_ID          NUMBER AUTOINCREMENT,
    NUMERO_FACTURE      STRING,
    ENTREPRISE_ID       NUMBER,
    DATE_EMISSION       DATE,
    DATE_ECHEANCE       DATE,
    MONTANT_HT          NUMBER(12,2),
    TVA                 NUMBER(12,2),
    MONTANT_TTC         NUMBER(12,2),
    STATUT              STRING,       -- PAYEE, EN_ATTENTE, EN_RETARD
    MODE_PAIEMENT       STRING,
    IBAN_CLIENT         STRING,
    REFERENCE_BANCAIRE  STRING
);

-- Table : transactions bancaires
CREATE OR REPLACE TABLE VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS (
    TRANSACTION_ID      NUMBER AUTOINCREMENT,
    DATE_TRANSACTION    TIMESTAMP_NTZ,
    TYPE_OPERATION      STRING,       -- VIREMENT, PRELEVEMENT, CB, CHEQUE
    MONTANT             NUMBER(12,2),
    DEVISE              STRING DEFAULT 'EUR',
    COMPTE_SOURCE       STRING,
    COMPTE_DESTINATION  STRING,
    IBAN_CONTREPARTIE   STRING,
    LIBELLE             STRING,
    REFERENCE           STRING,
    CATEGORIE           STRING
);

-- ────────────────────────────────────────────────────────────
-- 4. BASE DE DONNÉES : VOLTAIRE_DATALAKE (zone d'atterrissage)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE VOLTAIRE_DATALAKE;

CREATE SCHEMA VOLTAIRE_DATALAKE.RAW;
CREATE SCHEMA VOLTAIRE_DATALAKE.CURATED;

-- Table : logs d'accès (semi-structuré)
CREATE OR REPLACE TABLE VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS (
    LOG_ID              NUMBER AUTOINCREMENT,
    TIMESTAMP_EVENT     TIMESTAMP_NTZ,
    USER_EMAIL          STRING,
    IP_ADDRESS          STRING,
    USER_AGENT          STRING,
    ENDPOINT            STRING,
    HTTP_METHOD         STRING,
    RESPONSE_CODE       NUMBER,
    PAYLOAD             VARIANT
);

-- Table : données IoT (semi-structuré)
CREATE OR REPLACE TABLE VOLTAIRE_DATALAKE.RAW.IOT_TELEMETRY (
    EVENT_ID            NUMBER AUTOINCREMENT,
    DEVICE_ID           STRING,
    TIMESTAMP_EVENT     TIMESTAMP_NTZ,
    SENSOR_DATA         VARIANT,
    LOCATION            STRING,
    OPERATOR_NAME       STRING,
    OPERATOR_PHONE      STRING,
    OPERATOR_EMAIL      STRING
);

-- ────────────────────────────────────────────────────────────
-- 5. BASE DE DONNÉES : VOLTAIRE_GOVERNANCE (tags, profils, etc.)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE DATABASE VOLTAIRE_GOVERNANCE;

CREATE SCHEMA VOLTAIRE_GOVERNANCE.TAGS;
CREATE SCHEMA VOLTAIRE_GOVERNANCE.POLICIES;
CREATE SCHEMA VOLTAIRE_GOVERNANCE.CLASSIFICATION;

-- Tags personnalisés pour le tag_map
CREATE OR REPLACE TAG VOLTAIRE_GOVERNANCE.TAGS.SENSIBILITE
  ALLOWED_VALUES 'TRES_SENSIBLE', 'SENSIBLE', 'INTERNE', 'PUBLIC'
  COMMENT = 'Niveau de sensibilité des données — aligné ANSSI';

CREATE OR REPLACE TAG VOLTAIRE_GOVERNANCE.TAGS.RGPD
  ALLOWED_VALUES 'IDENTIFIANT_DIRECT', 'QUASI_IDENTIFIANT', 'DONNEE_SENSIBLE', 'NON_PERSONNEL'
  COMMENT = 'Catégorie RGPD pour classification des données personnelles';

CREATE OR REPLACE TAG VOLTAIRE_GOVERNANCE.TAGS.RETENTION
  ALLOWED_VALUES '30_JOURS', '1_AN', '3_ANS', '5_ANS', '10_ANS', 'ILLIMITEE'
  COMMENT = 'Durée de rétention réglementaire';

-- ────────────────────────────────────────────────────────────
-- 6. VUES (cross-database, simulent un usage production)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW VOLTAIRE_CRM.CLIENTS.V_ANNUAIRE_CONTACTS AS
SELECT
    p.PRENOM,
    p.NOM,
    p.EMAIL,
    p.TELEPHONE_PORTABLE,
    p.FONCTION,
    e.RAISON_SOCIALE,
    e.VILLE
FROM VOLTAIRE_CRM.CONTACTS.PERSONNES p
JOIN VOLTAIRE_CRM.CLIENTS.ENTREPRISES e
  ON p.ENTREPRISE_ID = e.ENTREPRISE_ID
WHERE e.ACTIF = TRUE;

CREATE OR REPLACE VIEW VOLTAIRE_RH.EMPLOYES.V_EFFECTIF_ACTIF AS
SELECT
    EMPLOYE_ID,
    PRENOM,
    NOM,
    EMAIL_PRO,
    POSTE,
    DEPARTEMENT,
    DATE_EMBAUCHE,
    TYPE_CONTRAT
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE ACTIF = TRUE;

CREATE OR REPLACE VIEW VOLTAIRE_FINANCE.COMPTABILITE.V_FACTURES_EN_RETARD AS
SELECT
    NUMERO_FACTURE,
    ENTREPRISE_ID,
    DATE_EMISSION,
    DATE_ECHEANCE,
    MONTANT_TTC,
    DATEDIFF('day', DATE_ECHEANCE, CURRENT_DATE()) AS JOURS_RETARD
FROM VOLTAIRE_FINANCE.COMPTABILITE.FACTURES
WHERE STATUT = 'EN_RETARD'
  AND DATE_ECHEANCE < CURRENT_DATE();

-- ────────────────────────────────────────────────────────────
-- 7. UDFs (simulent du code métier en production)
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION VOLTAIRE_CRM.CLIENTS.MASQUER_EMAIL(email STRING)
RETURNS STRING
LANGUAGE SQL
AS $$
    REGEXP_REPLACE(email, '(.{2}).+@', '\\1****@')
$$;

CREATE OR REPLACE FUNCTION VOLTAIRE_RH.EMPLOYES.CALCULER_ANCIENNETE(date_embauche DATE)
RETURNS NUMBER
LANGUAGE SQL
AS $$
    DATEDIFF('year', date_embauche, CURRENT_DATE())
$$;

CREATE OR REPLACE FUNCTION VOLTAIRE_FINANCE.COMPTABILITE.CALCULER_TVA(montant_ht NUMBER, taux NUMBER)
RETURNS NUMBER(12,2)
LANGUAGE SQL
AS $$
    ROUND(montant_ht * taux / 100, 2)
$$;

CREATE OR REPLACE FUNCTION VOLTAIRE_RH.EMPLOYES.VALIDER_NIR(nir STRING)
RETURNS BOOLEAN
LANGUAGE SQL
AS $$
    LENGTH(REGEXP_REPLACE(nir, '[^0-9]', '')) = 15
$$;

-- ────────────────────────────────────────────────────────────
-- 8. FILE FORMATS & STAGES pour le chargement
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FILE FORMAT VOLTAIRE_DATALAKE.RAW.CSV_FR
  TYPE = 'CSV'
  FIELD_DELIMITER = ';'
  RECORD_DELIMITER = '\n'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('', 'NULL', 'null')
  ENCODING = 'UTF-8'
  COMMENT = 'Format CSV français (séparateur point-virgule)';

CREATE OR REPLACE FILE FORMAT VOLTAIRE_DATALAKE.RAW.JSON_STANDARD
  TYPE = 'JSON'
  STRIP_OUTER_ARRAY = TRUE
  COMMENT = 'Format JSON standard';

CREATE OR REPLACE STAGE VOLTAIRE_DATALAKE.RAW.DATA_STAGE
  FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
  COMMENT = 'Stage pour chargement des données du workshop';

-- ────────────────────────────────────────────────────────────
-- 9. VÉRIFICATION
-- ────────────────────────────────────────────────────────────
SELECT 'Bases de données' AS OBJET, COUNT(*) AS NOMBRE
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME LIKE 'VOLTAIRE_%'
UNION ALL
SELECT 'Schémas', COUNT(*)
FROM VOLTAIRE_CRM.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA')
UNION ALL
SELECT 'Tables CRM', COUNT(*)
FROM VOLTAIRE_CRM.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'Tables RH', COUNT(*)
FROM VOLTAIRE_RH.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'Tables Finance', COUNT(*)
FROM VOLTAIRE_FINANCE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE';
