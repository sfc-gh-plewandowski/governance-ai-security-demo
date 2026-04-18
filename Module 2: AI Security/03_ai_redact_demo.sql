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
--
-- Pré-requis : Modules 2A–2C exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

CREATE DATABASE IF NOT EXISTS SECURITY_WORKSHOP;
USE DATABASE SECURITY_WORKSHOP;
USE SCHEMA PUBLIC;


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
        categories => ['NAME', 'EMAIL']
    ) AS NOMS_EMAILS_MASQUES,
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
-- NETTOYAGE
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

ALTER TABLE TRANSCRIPTIONS_SUPPORT
    MODIFY COLUMN TRANSCRIPTION
    UNSET MASKING POLICY;

DROP MASKING POLICY IF EXISTS MASK_TRANSCRIPTION_PII;
DROP TABLE IF EXISTS TRANSCRIPTIONS_REDACTEES;
DROP TABLE IF EXISTS TRANSCRIPTIONS_SUPPORT;
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
-- │  * CORTEX.GUARD n'est pas dispo sur eu-central-1         │
-- │                                                          │
-- │  → Module 2D : fermer la boucle avec le monitoring       │
-- └───────────────────────────────────────────────────────────┘
