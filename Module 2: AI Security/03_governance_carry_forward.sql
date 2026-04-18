-- ============================================================
-- MODULE 2C — LA PREUVE : LA GOUVERNANCE SE TRANSMET À L'AI
-- ============================================================
-- « On a gouverné les données (Dim 1), contrôlé les modèles
--   (Dim 2). Maintenant on PROUVE que tout fonctionne ensemble.
--   4 preuves formelles. Chacune répond à la question du RSSI :
--   "Si on ajoute l'AI, est-ce que ça respecte notre gouvernance ?" »
--
-- 4 preuves :
--   1. Masking    → le modèle reçoit des hash, pas des données
--   2. RAP        → le modèle ne connaît que les lignes autorisées
--   3. Projection → le modèle ne peut PAS accéder aux colonnes interdites
--   4. CRM        → le masking SIRET se transmet à l'AI
--
-- Durée : 25 min
-- Pré-requis : Modules 1A–1D + 2A–2B exécutés
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;
USE SECONDARY ROLES NONE;


-- ════════════════════════════════════════════════════════════
-- PREUVE 1 : LE MASKING SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════
-- On affiche côte à côte : ce que le rôle voit (colonnes brutes)
-- ET ce que le modèle résume. Le modèle ne peut pas deviner
-- les données originales — il travaille sur les données maskées.

-- A. SECURITY_ADMIN — données en clair → résumé avec vrais identifiants
USE ROLE SECURITY_ADMIN;

SELECT
  'SECURITY_ADMIN' AS ROLE_ACTIF,
  PRENOM, NOM,
  PERMIS_CONDUIRE AS PERMIS_VU_PAR_LE_ROLE,
  IBAN AS IBAN_VU_PAR_LE_ROLE,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici un profil employé. Résume en 1 phrase ce que tu vois : ' ||
    'Prénom: ' || PRENOM ||
    ', Nom: ' || NOM ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN ||
    ', Date naissance: ' || DATE_NAISSANCE::STRING
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 1;

-- B. DATA_ANALYST — données hashées → résumé avec hash
USE ROLE DATA_ANALYST;

SELECT
  'DATA_ANALYST' AS ROLE_ACTIF,
  PRENOM, NOM,
  PERMIS_CONDUIRE AS PERMIS_VU_PAR_LE_ROLE,
  IBAN AS IBAN_VU_PAR_LE_ROLE,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici un profil employé. Résume en 1 phrase ce que tu vois : ' ||
    'Prénom: ' || PRENOM ||
    ', Nom: ' || NOM ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN ||
    ', Date naissance: ' || DATE_NAISSANCE::STRING
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 3;

-- VÉRIFICATION :
-- Comparer PERMIS_VU_PAR_LE_ROLE avec le contenu de RESUME_AI.
-- SECURITY_ADMIN → le modèle cite le vrai numéro de permis
-- DATA_ANALYST   → le modèle voit un hash SHA2 → dit "identifiants hashés"


-- ════════════════════════════════════════════════════════════
-- PREUVE 2 : LA RAP SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════
-- Le modèle ne "connaît" que les lignes autorisées par la RAP.
-- SECURITY_ADMIN voit 1000 employés dans 15 départements.
-- DATA_ANALYST voit ~208 employés dans 3 départements.
-- Le modèle résume ce qu'il voit — pas ce qui existe.

-- C. SECURITY_ADMIN → connaissance complète
USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici une liste de ' || COUNT(*)::STRING || ' employés de Voltaire Analytics. ' ||
    'Les départements représentés sont : ' ||
    LISTAGG(DISTINCT DEPARTEMENT, ', ') ||
    '. Combien de départements y a-t-il ? Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

-- D. DATA_ANALYST → connaissance partielle (RAP filtre)
USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  COUNT(*) AS EMPLOYES_VISIBLES,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Voici une liste de ' || COUNT(*)::STRING || ' employés de Voltaire Analytics. ' ||
    'Les départements représentés sont : ' ||
    LISTAGG(DISTINCT DEPARTEMENT, ', ') ||
    '. Combien de départements y a-t-il ? Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL;

-- VÉRIFICATION :
-- SECURITY_ADMIN → "1000 employés dans 15 départements"
-- DATA_ANALYST   → "~208 employés dans 3 départements (Commercial, Marketing, Communication)"


-- ════════════════════════════════════════════════════════════
-- PREUVE 3 : LA PROJECTION SE TRANSMET AU MODÈLE
-- ════════════════════════════════════════════════════════════
-- La projection policy BLOQUE l'accès à une colonne entière.
-- Même via CORTEX.COMPLETE, impossible de lire le NIR.

-- E. DATA_ANALYST ne peut pas passer le NIR au modèle
USE ROLE DATA_ANALYST;

-- DÉCOMMENTER POUR DÉMONTRER L'ERREUR :
-- SELECT SNOWFLAKE.CORTEX.COMPLETE('mistral-large2',
--   'Voici le NIR de l''employé : ' || NIR
-- ) FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL WHERE EMPLOYE_ID = 3;

-- Erreur attendue :
-- "The following columns are restricted by a Projection Policy: NIR"
--
-- Même CORTEX.COMPLETE ne peut pas contourner une projection policy.
-- La colonne est invisible au niveau SQL — avant même que le
-- modèle n'entre en jeu.


-- ════════════════════════════════════════════════════════════
-- PREUVE 4 : CRM — LE MASKING SIRET SE TRANSMET À L'AI
-- ════════════════════════════════════════════════════════════
-- On sort du domaine RH pour vérifier sur un autre domaine :
-- le masking SIRET sur VOLTAIRE_CRM fonctionne pareil.

-- F. SECURITY_ADMIN → vrai SIRET
USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  RAISON_SOCIALE, SIRET,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Identifie cette entreprise : ' || RAISON_SOCIALE ||
    ', SIRET: ' || SIRET ||
    ', Secteur: ' || SECTEUR_ACTIVITE ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES
WHERE ENTREPRISE_ID = 1;

-- G. DATA_ANALYST → hash SHA2 au lieu du SIRET
USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  RAISON_SOCIALE, SIRET,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Identifie cette entreprise : ' || RAISON_SOCIALE ||
    ', SIRET: ' || SIRET ||
    ', Secteur: ' || SECTEUR_ACTIVITE ||
    '. Résume en 1 phrase.'
  ) AS RESUME_AI
FROM VOLTAIRE_CRM.CLIENTS.ENTREPRISES
WHERE ENTREPRISE_ID = 1;

-- VÉRIFICATION :
-- SECURITY_ADMIN → le modèle cite le vrai SIRET
-- DATA_ANALYST   → le modèle reçoit un hash SHA2, impossible d'identifier l'entreprise


-- ════════════════════════════════════════════════════════════
-- RESET
-- ════════════════════════════════════════════════════════════
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;

-- ┌───────────────────────────────────────────────────────────┐
-- │ RÉCAP MODULE 2C — 4 PREUVES FORMELLES                    │
-- │                                                          │
-- │  1. Masking → AI    : hash, pas données réelles          │
-- │  2. RAP → AI        : seules les lignes autorisées       │
-- │  3. Projection → AI : colonne entièrement bloquée        │
-- │  4. CRM → AI        : masking SIRET = même comportement  │
-- │                                                          │
-- │  « La gouvernance n'est pas héritée. Elle est résolue    │
-- │    à chaque requête — y compris les requêtes AI. »       │
-- │                                                          │
-- │  → Module 2D : contrôles complémentaires (AI_REDACT)     │
-- └───────────────────────────────────────────────────────────┘
