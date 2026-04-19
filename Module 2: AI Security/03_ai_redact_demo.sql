-- ============================================================
-- MODULE 2D — AI_REDACT & CONTRÔLES PROBABILISTES
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
--   5. Pipeline production : PDF → AI_PARSE → AI_REDACT → masking
--
-- Pré-requis : Modules 2A–2C exécutés
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
-- ACTE 5 : PIPELINE PRODUCTION — PDF → PARSE → REDACT → MASKING
-- ════════════════════════════════════════════════════════════
-- Pattern réel : des factures PDF arrivent sur un stage.
-- On extrait le texte (AI_PARSE_DOCUMENT), on redacte les PII
-- (AI_REDACT), et on protège la colonne brute par une masking
-- policy. Seuls les rôles privilégiés voient le texte original.
--
-- Pré-requis : 3 factures PDF uploadées dans le stage
--   (script invoices/ du repo grocery-chain-security)

USE ROLE ACCOUNTADMIN;
USE DATABASE SECURITY_WORKSHOP;

-- 5a. Créer le stage pour les factures PDF
CREATE OR REPLACE STAGE FACTURES_PDF
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Factures fournisseurs PDF pour démo AI_PARSE + AI_REDACT';

-- 5b. Uploader les factures (exécuter dans SnowSQL ou Snowsight)
-- PUT file:///path/to/invoices/FAC-2025-1001.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;
-- PUT file:///path/to/invoices/FAC-2025-1002.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;
-- PUT file:///path/to/invoices/FAC-2025-1003.pdf @FACTURES_PDF AUTO_COMPRESS=FALSE;

-- Vérifier que les fichiers sont bien sur le stage
LIST @FACTURES_PDF;
ALTER STAGE FACTURES_PDF REFRESH;

-- 5c. AI_PARSE_DOCUMENT — extraire le texte des PDF
SELECT
    RELATIVE_PATH AS FICHIER,
    SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
        @FACTURES_PDF,
        RELATIVE_PATH,
        {'mode': 'LAYOUT'}
    ):content::VARCHAR AS CONTENU_BRUT
FROM DIRECTORY(@FACTURES_PDF)
WHERE RELATIVE_PATH LIKE '%.pdf';

-- 5d. Pipeline complet : PARSE → REDACT → table sécurisée
CREATE OR REPLACE TABLE FACTURES_PARSED AS
WITH parsed AS (
    SELECT
        RELATIVE_PATH AS FICHIER,
        SNOWFLAKE.CORTEX.PARSE_DOCUMENT(
            @FACTURES_PDF,
            RELATIVE_PATH,
            {'mode': 'LAYOUT'}
        ):content::VARCHAR AS CONTENU_BRUT
    FROM DIRECTORY(@FACTURES_PDF)
    WHERE RELATIVE_PATH LIKE '%.pdf'
)
SELECT
    FICHIER,
    CONTENU_BRUT,
    SNOWFLAKE.CORTEX.AI_REDACT(CONTENU_BRUT) AS CONTENU_REDACTE,
    REGEXP_SUBSTR(CONTENU_BRUT, 'No Facture:\\s*(FAC-[\\d-]+)', 1, 1, 'e') AS NO_FACTURE,
    REGEXP_SUBSTR(CONTENU_BRUT, 'TOTAL TTC:\\s+([\\d.]+)', 1, 1, 'e')::NUMBER(12,2) AS TOTAL_TTC
FROM parsed;

-- Vérifier : colonnes brutes vs redactées
SELECT
    NO_FACTURE,
    TOTAL_TTC,
    LEFT(CONTENU_BRUT, 200) AS APERCU_BRUT,
    LEFT(CONTENU_REDACTE, 200) AS APERCU_REDACTE
FROM FACTURES_PARSED;

-- 5e. Masking policy sur la colonne brute
CREATE OR REPLACE MASKING POLICY MASK_FACTURE_BRUT
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('SECURITY_ADMIN') THEN val
        ELSE SNOWFLAKE.CORTEX.AI_REDACT(val)
    END;

ALTER TABLE FACTURES_PARSED
    MODIFY COLUMN CONTENU_BRUT
    SET MASKING POLICY MASK_FACTURE_BRUT;

GRANT SELECT ON TABLE FACTURES_PARSED TO ROLE SECURITY_ADMIN;
GRANT SELECT ON TABLE FACTURES_PARSED TO ROLE DATA_ANALYST;
GRANT SELECT ON TABLE FACTURES_PARSED TO ROLE DATA_ENGINEER;

USE SECONDARY ROLES NONE;

-- SECURITY_ADMIN → voit les IBAN, SIRET, noms, adresses
USE ROLE SECURITY_ADMIN;
SELECT NO_FACTURE, LEFT(CONTENU_BRUT, 200) AS APERCU
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PARSED
WHERE NO_FACTURE = 'FAC-2025-1001';

-- DATA_ANALYST → PII masquées automatiquement par AI_REDACT
USE ROLE DATA_ANALYST;
SELECT NO_FACTURE, LEFT(CONTENU_BRUT, 200) AS APERCU
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PARSED
WHERE NO_FACTURE = 'FAC-2025-1001';

-- Tous les rôles voient la colonne redactée (pas de policy dessus)
SELECT NO_FACTURE, TOTAL_TTC, LEFT(CONTENU_REDACTE, 200) AS APERCU_SAFE
FROM SECURITY_WORKSHOP.PUBLIC.FACTURES_PARSED;


-- ════════════════════════════════════════════════════════════
-- NETTOYAGE
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

ALTER TABLE TRANSCRIPTIONS_SUPPORT
    MODIFY COLUMN TRANSCRIPTION
    UNSET MASKING POLICY;

ALTER TABLE FACTURES_PARSED
    MODIFY COLUMN CONTENU_BRUT
    UNSET MASKING POLICY;

DROP MASKING POLICY IF EXISTS MASK_TRANSCRIPTION_PII;
DROP MASKING POLICY IF EXISTS MASK_FACTURE_BRUT;
DROP TABLE IF EXISTS TRANSCRIPTIONS_REDACTEES;
DROP TABLE IF EXISTS TRANSCRIPTIONS_SUPPORT;
DROP TABLE IF EXISTS FACTURES_PARSED;
DROP STAGE IF EXISTS FACTURES_PDF;
DROP DATABASE IF EXISTS SECURITY_WORKSHOP;

-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2D — CONTRÔLES PROBABILISTES                │
-- │                                                          │
-- │  Déterministe (matin)  = murs (masking, RAP, projection) │
-- │  Probabiliste (AI)     = filets (AI_REDACT, GUARD*)      │
-- │                                                          │
-- │  AI_REDACT comble le fossé entre colonnes structurées     │
-- │  (masking) et texte libre (PII dans du non-structuré).   │
-- │                                                          │
-- │  Pattern production : AI_REDACT dans une masking policy   │
-- │  → gouvernance automatique pour le texte libre.          │
-- │                                                          │
-- │  Pipeline PDF : AI_PARSE_DOCUMENT → AI_REDACT → masking  │
-- │  → les factures sont exploitables sans exposer les PII.  │
-- │                                                          │
-- │  * CORTEX.GUARD n'est pas dispo sur eu-central-1         │
-- │                                                          │
-- │  → Module 2D : fermer la boucle avec le monitoring       │
-- └───────────────────────────────────────────────────────────┘
