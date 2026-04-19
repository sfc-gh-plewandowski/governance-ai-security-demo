-- CERT: D5 Securing AI/ML (12%) + D2 Data Protection (30%) — AI_REDACT, masking policies, production pipeline
-- ============================================================
-- MODULE 2C — AI_REDACT & CONTRÔLES PROBABILISTES
-- ============================================================
-- AI_REDACT détecte et masque les PII dans du texte libre,
-- là où le masking par colonne ne peut pas aider.
--
-- Best practice : contrôles déterministes (masking, RAP,
-- projection) = murs. Contrôles probabilistes (AI_REDACT,
-- GUARD) = filets de sécurité. Utiliser les deux.
--
-- Ce module couvre :
--   1. Données brutes avec PII dans du texte libre
--   2. AI_REDACT : redact + detect + catégories sélectives
--   3. Pipeline : AI_REDACT → AI_SENTIMENT (analyse sécurisée)
--   4. Intégration gouvernance : AI_REDACT dans une masking policy
--   5. Pipeline production : PDF → PARSE → EXTRACT → masking + AI_REDACT
--
-- Pré-requis : Modules 2A–2B exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

CREATE DATABASE IF NOT EXISTS SECURITY_WORKSHOP;
USE DATABASE SECURITY_WORKSHOP;
USE SCHEMA PUBLIC;

GRANT USAGE ON DATABASE SECURITY_WORKSHOP TO ROLE SECURITY_ADMIN;
GRANT USAGE ON DATABASE SECURITY_WORKSHOP TO ROLE DATA_ANALYST;
GRANT USAGE ON DATABASE SECURITY_WORKSHOP TO ROLE DATA_ENGINEER;
GRANT USAGE ON SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE SECURITY_ADMIN;
GRANT USAGE ON SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ANALYST;
GRANT USAGE ON SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ENGINEER;
GRANT SELECT ON ALL TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE SECURITY_ADMIN;
GRANT SELECT ON ALL TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ENGINEER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE SECURITY_ADMIN;
GRANT SELECT ON FUTURE TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA SECURITY_WORKSHOP.PUBLIC TO ROLE DATA_ENGINEER;

-- ════════════════════════════════════════════════════════════
-- ACTE 1 : DES PII DANS DU TEXTE LIBRE
-- ════════════════════════════════════════════════════════════
-- Scénario : transcriptions de support client.
-- Les PII sont mélangées dans du texte non structuré.
-- Le masking par colonne ne peut rien faire ici.

CREATE OR REPLACE TABLE TRANSCRIPTIONS_SUPPORT (
    TICKET_ID NUMBER AUTOINCREMENT,
    AGENT STRING,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TRANSCRIPTION STRING
);

INSERT INTO TRANSCRIPTIONS_SUPPORT (AGENT, TRANSCRIPTION)
VALUES
('Agent_01',
 'Le client Jean-Pierre Martin a appelé au sujet de son compte. Son email est jp.martin@gmail.com et son téléphone est 06 12 34 56 78. Il habite au 15 rue de la Paix, 75002 Paris. Son numéro de sécurité sociale est 1 85 12 75 108 042 57. Il signale des débits non autorisés sur sa carte Visa se terminant par 4242.'),

('Agent_02',
 'Échange avec Marie Dupont concernant un litige de facturation. Contact : marie.dupont@outlook.fr ou +33 6 98 76 54 32. Date de naissance : 15 mars 1988. Son passeport est 22AB12345. Elle mentionne son mari Pierre, 42 ans.'),

('Agent_03',
 'Appel de David Chen, adresse IP 192.168.1.42. Il doit mettre à jour son permis de conduire : 0512345678901. Son IBAN est FR76 3000 6000 0112 3456 7890 189. Carte de paiement : 5500 0000 0000 0004, exp 12/27. Adresse : 8 avenue des Champs-Élysées, 75008 Paris.'),

('Agent_04',
 'Escalade d''Eve Martinez, DPO chez Acme Corp. Elle signale que les dossiers des employés Bob Wilson (SSN 234-56-7890, né le 22/07/1990) et Carol Davis (email carol.davis@acme.com, salaire 150 000 €) ont été partagés par erreur. Contact Eve : eve.martinez@acme.com ou +44 20 7946 0958.'),

('Agent_05',
 'Ticket technique de François Leclerc. Homme, 33 ans, basé à Lyon. IP : 10.0.1.15. Carte bancaire : 3530 1113 3330 0000. Adresse professionnelle : 200 cours Lafayette, 69003 Lyon. Email : f.leclerc@entreprise.fr.');

-- Voir les données brutes — PII partout
SELECT TICKET_ID, AGENT, TRANSCRIPTION
FROM TRANSCRIPTIONS_SUPPORT
ORDER BY TICKET_ID;


-- ════════════════════════════════════════════════════════════
-- ACTE 2 : AI_REDACT EN ACTION
-- ════════════════════════════════════════════════════════════

-- 2a. Redaction complète — remplace les PII par [CATÉGORIE]
SELECT
    TICKET_ID,
    TRANSCRIPTION AS ORIGINAL,
    AI_REDACT(TRANSCRIPTION) AS REDACTE
FROM TRANSCRIPTIONS_SUPPORT
ORDER BY TICKET_ID;

-- 2b. Mode DETECT — inventaire des PII sans modifier le texte
SELECT
    t.TICKET_ID,
    s.value:category::STRING AS CATEGORIE_PII,
    s.value:text::STRING AS VALEUR_DETECTEE,
    s.value:start::NUMBER AS DEBUT,
    s.value:end::NUMBER AS FIN
FROM TRANSCRIPTIONS_SUPPORT t,
    LATERAL FLATTEN(
        input => AI_REDACT(
            input => t.TRANSCRIPTION,
            return_error_details => FALSE,
            mode => 'detect'
        ):spans
    ) s
ORDER BY t.TICKET_ID, DEBUT;

-- 2c. Synthèse par catégorie — combien de PII de chaque type ?
SELECT
    s.value:category::STRING AS CATEGORIE_PII,
    COUNT(*) AS NB_OCCURRENCES
FROM TRANSCRIPTIONS_SUPPORT t,
    LATERAL FLATTEN(
        input => AI_REDACT(
            input => t.TRANSCRIPTION,
            return_error_details => FALSE,
            mode => 'detect'
        ):spans
    ) s
GROUP BY CATEGORIE_PII
ORDER BY NB_OCCURRENCES DESC;

-- 2d. Redaction sélective — ne masquer que certaines catégories
SELECT
    TICKET_ID,
    AI_REDACT(
        input => TRANSCRIPTION,
        categories => ['NATIONAL_ID', 'PAYMENT_CARD_DATA']
    ) AS IDS_FINANCIERS_MASQUES
FROM TRANSCRIPTIONS_SUPPORT
WHERE TICKET_ID = 3;


-- ════════════════════════════════════════════════════════════
-- ACTE 3 : PIPELINE — REDACT PUIS ANALYSE
-- ════════════════════════════════════════════════════════════
-- Pattern production : redact d'abord, analyse ensuite.
-- Le modèle d'analyse ne voit jamais les PII.

CREATE OR REPLACE TABLE TRANSCRIPTIONS_REDACTEES AS
SELECT
    TICKET_ID,
    AGENT,
    CREATED_AT,
    AI_REDACT(TRANSCRIPTION) AS TRANSCRIPTION_SAFE
FROM TRANSCRIPTIONS_SUPPORT;

SELECT
    TICKET_ID,
    AGENT,
    TRANSCRIPTION_SAFE,
    SNOWFLAKE.CORTEX.SENTIMENT(TRANSCRIPTION_SAFE) AS SCORE_SENTIMENT
FROM TRANSCRIPTIONS_REDACTEES
ORDER BY SCORE_SENTIMENT ASC;


-- ════════════════════════════════════════════════════════════
-- ACTE 4 : INTÉGRATION GOUVERNANCE — AI_REDACT DANS UNE MASKING POLICY
-- ════════════════════════════════════════════════════════════
-- Le pattern ultime : les rôles privilégiés voient le texte brut,
-- tous les autres voient le texte automatiquement redacté.
-- C'est du masking dynamique alimenté par l'AI.

CREATE OR REPLACE MASKING POLICY MASK_TRANSCRIPTION_PII
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        WHEN IS_ROLE_IN_SESSION('DATA_ENGINEER') THEN val
        ELSE AI_REDACT(val)
    END;

ALTER TABLE TRANSCRIPTIONS_SUPPORT
    MODIFY COLUMN TRANSCRIPTION
    SET MASKING POLICY MASK_TRANSCRIPTION_PII;

USE SECONDARY ROLES NONE;

-- SECURITY_ADMIN → PII visibles
USE ROLE SECURITY_ADMIN;
SELECT TICKET_ID, LEFT(TRANSCRIPTION, 150) || '...' AS APERCU
FROM SECURITY_WORKSHOP.PUBLIC.TRANSCRIPTIONS_SUPPORT
WHERE TICKET_ID = 1;

-- DATA_ANALYST → PII automatiquement redactées par la policy !
USE ROLE DATA_ANALYST;
SELECT TICKET_ID, LEFT(TRANSCRIPTION, 150) || '...' AS APERCU
FROM SECURITY_WORKSHOP.PUBLIC.TRANSCRIPTIONS_SUPPORT
WHERE TICKET_ID = 1;


-- ════════════════════════════════════════════════════════════
-- ACTE 5 : PIPELINE PRODUCTION — PDF → PARSE → EXTRACT → GOUVERNANCE
-- ════════════════════════════════════════════════════════════
-- Pattern production réel :
--   1. AI_PARSE_DOCUMENT  → extrait le texte brut du PDF
--   2. AI_EXTRACT         → extrait les champs structurés
--   3. On stocke les DEUX : texte brut + colonnes structurées
--   4. Masking policies   → colonnes structurées (déterministe)
--   5. AI_REDACT          → colonne texte brut (probabiliste)
--
-- Résultat : chaque type de donnée est protégé par le bon outil.
--   Structuré (IBAN, email, tél) → masking policy classique
--   Non-structuré (texte libre)  → AI_REDACT via masking policy
--
-- Pré-requis : 3 factures PDF uploadées dans le stage
--   (data/factures_demo.zip dans le repo)

USE ROLE ACCOUNTADMIN;
USE DATABASE SECURITY_WORKSHOP;

-- 5a. Créer le stage pour les factures PDF
CREATE OR REPLACE STAGE FACTURES_PDF
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Factures fournisseurs PDF pour démo pipeline production';

-- 5b. Uploader les factures (exécuter dans SnowSQL ou Snowsight)
-- PUT file:///path/to/data/FAC-2025-1001.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;
-- PUT file:///path/to/data/FAC-2025-1002.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;
-- PUT file:///path/to/data/FAC-2025-1003.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;

LIST @FACTURES_PDF;
ALTER STAGE FACTURES_PDF REFRESH;

-- 5c. ÉTAPE 1 : AI_PARSE_DOCUMENT — texte brut du PDF
SELECT
    RELATIVE_PATH AS FICHIER,
    LEFT(SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        @FACTURES_PDF, RELATIVE_PATH, {'mode': 'LAYOUT'}
    ):content::VARCHAR, 300) AS APERCU_TEXTE_BRUT
FROM DIRECTORY(@FACTURES_PDF)
WHERE RELATIVE_PATH LIKE '%.pdf';

-- 5d. ÉTAPE 2 : AI_EXTRACT — champs structurés depuis le texte
-- AI_EXTRACT retourne {"error": null, "response": {champs...}}
-- Les valeurs sont sous :response:<nom_champ>
SELECT
    RELATIVE_PATH AS FICHIER,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
            @FACTURES_PDF, RELATIVE_PATH, {'mode': 'LAYOUT'}
        ):content::VARCHAR,
        ['invoice_number', 'supplier_name', 'supplier_email',
         'supplier_phone', 'supplier_iban', 'supplier_siret',
         'total_ttc', 'tva_rate']
    ) AS CHAMPS_EXTRAITS
FROM DIRECTORY(@FACTURES_PDF)
WHERE RELATIVE_PATH LIKE '%.pdf';

-- 5e. ÉTAPE 3 : Construire la table production (structuré + brut)
-- On garde les colonnes structurées ET le texte brut dans la même table.
CREATE OR REPLACE TABLE FACTURES_PRODUCTION AS
WITH parsed AS (
    SELECT
        RELATIVE_PATH AS FICHIER,
        SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
            @FACTURES_PDF, RELATIVE_PATH, {'mode': 'LAYOUT'}
        ):content::VARCHAR AS CONTENU_BRUT
    FROM DIRECTORY(@FACTURES_PDF)
    WHERE RELATIVE_PATH LIKE '%.pdf'
),
extracted AS (
    SELECT
        FICHIER,
        CONTENU_BRUT,
        SNOWFLAKE.CORTEX.AI_EXTRACT(CONTENU_BRUT,
            ['invoice_number', 'supplier_name', 'supplier_email',
             'supplier_phone', 'supplier_iban', 'supplier_siret',
             'total_ttc', 'tva_rate']
        ) AS E
    FROM parsed
)
SELECT
    FICHIER,
    E:response:invoice_number::STRING    AS NO_FACTURE,
    E:response:supplier_name::STRING     AS FOURNISSEUR,
    E:response:supplier_email::STRING    AS EMAIL_FOURNISSEUR,
    E:response:supplier_phone::STRING    AS TEL_FOURNISSEUR,
    E:response:supplier_iban::STRING     AS IBAN_FOURNISSEUR,
    E:response:supplier_siret::STRING    AS SIRET_FOURNISSEUR,
    E:response:total_ttc::NUMBER(12,2)   AS TOTAL_TTC,
    E:response:tva_rate::STRING          AS TVA_POURCENT,
    CONTENU_BRUT
FROM extracted;

SELECT * FROM FACTURES_PRODUCTION;

-- 5f. ÉTAPE 4 : Masking policies sur les colonnes STRUCTURÉES
-- Même approche que le Module 1 — déterministe, par colonne.
CREATE OR REPLACE MASKING POLICY MASK_IBAN
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        ELSE '****' || RIGHT(val, 4)
    END;

CREATE OR REPLACE MASKING POLICY MASK_CONTACT
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        ELSE '***MASQUÉ***'
    END;

ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN IBAN_FOURNISSEUR SET MASKING POLICY MASK_IBAN;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN EMAIL_FOURNISSEUR SET MASKING POLICY MASK_CONTACT;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN TEL_FOURNISSEUR SET MASKING POLICY MASK_CONTACT;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN SIRET_FOURNISSEUR SET MASKING POLICY MASK_CONTACT;

-- 5g. ÉTAPE 5 : AI_REDACT sur la colonne NON-STRUCTURÉE
-- Le texte brut contient les mêmes PII + d'autres non extraites.
-- AI_REDACT attrape tout ce qui est dans le texte libre.
CREATE OR REPLACE MASKING POLICY MASK_FACTURE_BRUT
AS (val STRING) RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        ELSE SNOWFLAKE.CORTEX.AI_REDACT(val)
    END;

ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN CONTENU_BRUT SET MASKING POLICY MASK_FACTURE_BRUT;

GRANT SELECT ON TABLE FACTURES_PRODUCTION TO ROLE SECURITY_ADMIN;
GRANT SELECT ON TABLE FACTURES_PRODUCTION TO ROLE DATA_ANALYST;
GRANT SELECT ON TABLE FACTURES_PRODUCTION TO ROLE DATA_ENGINEER;

-- 5h. TEST : comparer les vues par rôle
USE SECONDARY ROLES NONE;

-- SECURITY_ADMIN → tout visible (IBAN, email, tél, texte brut complet)
USE ROLE SECURITY_ADMIN;
SELECT NO_FACTURE, FOURNISSEUR, EMAIL_FOURNISSEUR, TEL_FOURNISSEUR,
       IBAN_FOURNISSEUR, LEFT(CONTENU_BRUT, 150) AS APERCU_BRUT
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PRODUCTION;

-- DATA_ANALYST → structuré masqué (déterministe) + brut redacté (AI)
USE ROLE DATA_ANALYST;
SELECT NO_FACTURE, FOURNISSEUR, EMAIL_FOURNISSEUR, TEL_FOURNISSEUR,
       IBAN_FOURNISSEUR, LEFT(CONTENU_BRUT, 150) AS APERCU_BRUT
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PRODUCTION;

-- DATA_ANALYST voit quand même les montants (pas de PII)
SELECT NO_FACTURE, FOURNISSEUR, TOTAL_TTC, TVA_POURCENT
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PRODUCTION;


-- ════════════════════════════════════════════════════════════
-- NETTOYAGE
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

ALTER TABLE TRANSCRIPTIONS_SUPPORT
    MODIFY COLUMN TRANSCRIPTION
    UNSET MASKING POLICY;

ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN CONTENU_BRUT
    UNSET MASKING POLICY;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN IBAN_FOURNISSEUR
    UNSET MASKING POLICY;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN EMAIL_FOURNISSEUR
    UNSET MASKING POLICY;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN TEL_FOURNISSEUR
    UNSET MASKING POLICY;
ALTER TABLE FACTURES_PRODUCTION
    MODIFY COLUMN SIRET_FOURNISSEUR
    UNSET MASKING POLICY;

DROP MASKING POLICY IF EXISTS MASK_TRANSCRIPTION_PII;
DROP MASKING POLICY IF EXISTS MASK_FACTURE_BRUT;
DROP MASKING POLICY IF EXISTS MASK_IBAN;
DROP MASKING POLICY IF EXISTS MASK_CONTACT;
DROP TABLE IF EXISTS TRANSCRIPTIONS_REDACTEES;
DROP TABLE IF EXISTS TRANSCRIPTIONS_SUPPORT;
DROP TABLE IF EXISTS FACTURES_PRODUCTION;
DROP STAGE IF EXISTS FACTURES_PDF;
DROP DATABASE IF EXISTS SECURITY_WORKSHOP;

-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2C — CONTRÔLES PROBABILISTES                │
-- │                                                          │
-- │  Déterministe (matin)  = murs (masking, RAP, projection) │
-- │  Probabiliste (AI)     = filets (AI_REDACT, GUARD*)      │
-- │                                                          │
-- │  AI_REDACT comble le fossé entre colonnes structurées     │
-- │  (masking) et texte libre (PII dans du non-structuré).   │
-- │                                                          │
-- │  Pattern production :                                    │
-- │    Colonnes structurées → masking policies (déterministe) │
-- │    Texte brut           → AI_REDACT via policy (probab.) │
-- │                                                          │
-- │  Pipeline PDF complet :                                  │
-- │    AI_PARSE → AI_EXTRACT → table production              │
-- │    → masking (structuré) + AI_REDACT (non-structuré)     │
-- │                                                          │
-- │  * CORTEX.GUARD n'est pas dispo sur eu-central-1         │
-- │                                                          │
-- │  → Module 2D : fermer la boucle avec le monitoring       │
-- └───────────────────────────────────────────────────────────┘
