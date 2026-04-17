-- ============================================================
-- MODULE 1A — ÉTAPE 2 : CHARGEMENT DES DONNÉES
-- ============================================================
-- Charge les fichiers CSV et JSON dans les tables créées
-- à l'étape 1. Utilise un stage interne + COPY INTO.
--
-- Pré-requis : 01_account_setup.sql exécuté
-- Fichiers attendus dans le stage : /data/*.csv, /data/*.json
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- 1. UPLOAD DES FICHIERS VERS LE STAGE
-- ────────────────────────────────────────────────────────────
-- Exécuter ces commandes depuis SnowSQL ou le panneau PUT de Snowsight.
-- Si vous êtes dans Snowsight, utilisez le bouton "Upload" sur le stage.
--
-- Depuis SnowSQL :
--   PUT file:///chemin/vers/data/entreprises.csv     @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/contacts.csv        @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/employes.csv        @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/bulletins_paie.csv  @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/candidats.csv       @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/factures.csv        @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/transactions.json   @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/json/ AUTO_COMPRESS=FALSE;
--   PUT file:///chemin/vers/data/access_logs.json    @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/json/ AUTO_COMPRESS=FALSE;

-- Vérification du stage :
LIST @VOLTAIRE_DATALAKE.RAW.DATA_STAGE;

-- ────────────────────────────────────────────────────────────
-- 2. CHARGEMENT CSV : ENTREPRISES
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_CRM.CLIENTS.ENTREPRISES
    (RAISON_SOCIALE, SIRET, SIREN, NUM_TVA, ADRESSE, CODE_POSTAL, VILLE,
     PAYS, TELEPHONE, EMAIL_CONTACT, SITE_WEB, SECTEUR_ACTIVITE,
     CHIFFRE_AFFAIRES, DATE_CREATION, ACTIF)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/entreprises.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 3. CHARGEMENT CSV : CONTACTS
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_CRM.CONTACTS.PERSONNES
    (ENTREPRISE_ID, PRENOM, NOM, EMAIL, TELEPHONE_PORTABLE, TELEPHONE_FIXE,
     FONCTION, DATE_NAISSANCE, GENRE, ADRESSE_PERSO, CODE_POSTAL_PERSO,
     VILLE_PERSO, NATIONALITE)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/contacts.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 4. CHARGEMENT CSV : EMPLOYÉS
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_RH.EMPLOYES.PERSONNEL
    (PRENOM, NOM, EMAIL_PRO, TELEPHONE_PRO, TELEPHONE_PERSO, DATE_NAISSANCE,
     LIEU_NAISSANCE, GENRE, NATIONALITE, NIR, NUMERO_PASSEPORT, PERMIS_CONDUIRE,
     ADRESSE, CODE_POSTAL, VILLE, IBAN, POSTE, DEPARTEMENT, DATE_EMBAUCHE,
     TYPE_CONTRAT, MANAGER_ID, ACTIF)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/employes.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 5. CHARGEMENT CSV : BULLETINS DE PAIE
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_RH.PAIE.BULLETINS
    (EMPLOYE_ID, MOIS, SALAIRE_BRUT, SALAIRE_NET, COTISATIONS, PRIMES,
     HEURES_SUPPLEMENTAIRES, DATE_VIREMENT, IBAN_VERSEMENT)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/bulletins_paie.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 6. CHARGEMENT CSV : CANDIDATS
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_RH.RECRUTEMENT.CANDIDATS
    (PRENOM, NOM, EMAIL, TELEPHONE, DATE_NAISSANCE, ADRESSE, CODE_POSTAL,
     VILLE, DIPLOME, ANNEES_EXPERIENCE, POSTE_VISE, SALAIRE_SOUHAITE,
     DATE_CANDIDATURE, STATUT)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/candidats.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 7. CHARGEMENT CSV : FACTURES
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_FINANCE.COMPTABILITE.FACTURES
    (NUMERO_FACTURE, ENTREPRISE_ID, DATE_EMISSION, DATE_ECHEANCE, MONTANT_HT,
     TVA, MONTANT_TTC, STATUT, MODE_PAIEMENT, IBAN_CLIENT, REFERENCE_BANCAIRE)
FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/csv/factures.csv
FILE_FORMAT = VOLTAIRE_DATALAKE.RAW.CSV_FR
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 8. CHARGEMENT JSON : TRANSACTIONS
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS
    (DATE_TRANSACTION, TYPE_OPERATION, MONTANT, DEVISE, COMPTE_SOURCE,
     COMPTE_DESTINATION, IBAN_CONTREPARTIE, LIBELLE, REFERENCE, CATEGORIE)
FROM (
    SELECT
        $1:DATE_TRANSACTION::TIMESTAMP_NTZ,
        $1:TYPE_OPERATION::STRING,
        $1:MONTANT::NUMBER(12,2),
        $1:DEVISE::STRING,
        $1:COMPTE_SOURCE::STRING,
        $1:COMPTE_DESTINATION::STRING,
        $1:IBAN_CONTREPARTIE::STRING,
        $1:LIBELLE::STRING,
        $1:REFERENCE::STRING,
        $1:CATEGORIE::STRING
    FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/json/transactions.json
        (FILE_FORMAT => VOLTAIRE_DATALAKE.RAW.JSON_STANDARD)
)
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 9. CHARGEMENT JSON : ACCESS LOGS
-- ────────────────────────────────────────────────────────────
COPY INTO VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS
    (TIMESTAMP_EVENT, USER_EMAIL, IP_ADDRESS, USER_AGENT, ENDPOINT,
     HTTP_METHOD, RESPONSE_CODE, PAYLOAD)
FROM (
    SELECT
        $1:TIMESTAMP_EVENT::TIMESTAMP_NTZ,
        $1:USER_EMAIL::STRING,
        $1:IP_ADDRESS::STRING,
        $1:USER_AGENT::STRING,
        $1:ENDPOINT::STRING,
        $1:HTTP_METHOD::STRING,
        $1:RESPONSE_CODE::NUMBER,
        $1:PAYLOAD::VARIANT
    FROM @VOLTAIRE_DATALAKE.RAW.DATA_STAGE/json/access_logs.json
        (FILE_FORMAT => VOLTAIRE_DATALAKE.RAW.JSON_STANDARD)
)
ON_ERROR = 'CONTINUE';

-- ────────────────────────────────────────────────────────────
-- 10. VÉRIFICATION : COMPTAGE PAR TABLE
-- ────────────────────────────────────────────────────────────
SELECT 'ENTREPRISES' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES
UNION ALL SELECT 'CONTACTS', COUNT(*) FROM VOLTAIRE_CRM.CONTACTS.PERSONNES
UNION ALL SELECT 'EMPLOYES', COUNT(*) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
UNION ALL SELECT 'BULLETINS_PAIE', COUNT(*) FROM VOLTAIRE_RH.PAIE.BULLETINS
UNION ALL SELECT 'CANDIDATS', COUNT(*) FROM VOLTAIRE_RH.RECRUTEMENT.CANDIDATS
UNION ALL SELECT 'FACTURES', COUNT(*) FROM VOLTAIRE_FINANCE.COMPTABILITE.FACTURES
UNION ALL SELECT 'TRANSACTIONS', COUNT(*) FROM VOLTAIRE_FINANCE.TRESORERIE.TRANSACTIONS
UNION ALL SELECT 'ACCESS_LOGS', COUNT(*) FROM VOLTAIRE_DATALAKE.RAW.ACCESS_LOGS
ORDER BY TABLE_NAME;

-- Aperçu rapide : données françaises bien chargées ?
SELECT PRENOM, NOM, NIR, NUMERO_PASSEPORT, PERMIS_CONDUIRE, IBAN, TELEPHONE_PERSO
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
LIMIT 5;
