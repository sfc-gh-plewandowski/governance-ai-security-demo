-- ============================================================
-- MODULE 2A — LE FLUX D'INFÉRENCE AI ET LA FRONTIÈRE DE CONFIANCE
-- ============================================================
-- Ce module est surtout CONCEPTUEL. Le SQL ici sert à
-- illustrer les paramètres et vérifier la configuration.
--
-- L'objectif : comprendre le flux complet d'une requête AI
-- et identifier OÙ chaque dimension de gouvernance s'applique.
--
-- Pré-requis : Modules 1A–1C exécutés (gouvernance en place)
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ────────────────────────────────────────────────────────────
-- A. VÉRIFIER LA CONFIGURATION CORTEX DU COMPTE
-- ────────────────────────────────────────────────────────────

SHOW PARAMETERS LIKE 'CORTEX%' IN ACCOUNT;

-- ────────────────────────────────────────────────────────────
-- B. CORTEX_ENABLED_CROSS_REGION — OÙ VOS DONNÉES VOYAGENT
-- ────────────────────────────────────────────────────────────
-- Valeurs possibles :
--   DISABLED      → tout reste dans la région du compte
--   AWS_EU        → peut aller vers d'autres régions AWS en EU
--   AWS_US_EU     → peut traverser US et EU sur AWS
--   AZURE_EU      → peut aller vers Azure EU
--
-- IMPACT RGPD : si le compte est en eu-central-1 et qu'on
-- active AWS_US, les données transitent hors UE pendant
-- l'inférence. Le DPO doit le savoir.

SELECT CURRENT_REGION() AS REGION_COMPTE;

-- Pour démontrer le changement (NE PAS EXÉCUTER EN PROD SANS VALIDATION) :
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'DISABLED';
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU';

-- ────────────────────────────────────────────────────────────
-- C. TEST DE BASE — CORTEX.COMPLETE FONCTIONNE
-- ────────────────────────────────────────────────────────────

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'En une phrase, explique ce qu''est le masking dynamique dans Snowflake.'
) AS REPONSE_AI;

-- ────────────────────────────────────────────────────────────
-- D. LE FLUX D'INFÉRENCE — DÉMONSTRATION VISUELLE
-- ────────────────────────────────────────────────────────────
-- Ce SQL montre que le modèle reçoit les données APRÈS
-- que la gouvernance a été appliquée. On passe une ligne
-- de données au modèle — le contenu dépend du rôle.

USE SECONDARY ROLES NONE;

USE ROLE SECURITY_ADMIN;
SELECT 'SECURITY_ADMIN' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Résume ce profil employé en 2 lignes : ' ||
    'Nom: ' || PRENOM || ' ' || NOM ||
    ', Département: ' || DEPARTEMENT ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 1;

USE ROLE DATA_ANALYST;
SELECT 'DATA_ANALYST' AS ROLE_ACTIF,
  SNOWFLAKE.CORTEX.COMPLETE(
    'mistral-large2',
    'Résume ce profil employé en 2 lignes : ' ||
    'Nom: ' || PRENOM || ' ' || NOM ||
    ', Département: ' || DEPARTEMENT ||
    ', Permis: ' || PERMIS_CONDUIRE ||
    ', IBAN: ' || IBAN
  ) AS RESUME_AI
FROM VOLTAIRE_RH.EMPLOYES.PERSONNEL
WHERE EMPLOYE_ID = 3;

-- SECURITY_ADMIN : le modèle reçoit les vraies données (permis en clair, IBAN complet)
-- DATA_ANALYST : le modèle reçoit des hash SHA2 → il résume des hash, pas des données réelles
-- LA GOUVERNANCE EST APPLIQUÉE AVANT QUE LE MODÈLE NE VOIE LES DONNÉES

-- ────────────────────────────────────────────────────────────
-- E. RESET
-- ────────────────────────────────────────────────────────────

USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;
