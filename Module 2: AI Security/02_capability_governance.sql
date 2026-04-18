-- ============================================================
-- MODULE 2B — GOUVERNANCE DES CAPACITÉS (DIMENSION 2)
-- ============================================================
-- Dimension 2 : qui peut utiliser quel modèle, quel agent,
-- quels outils. On ne contrôle pas juste les DONNÉES (Dim 1),
-- on contrôle aussi les CAPACITÉS AI elles-mêmes.
--
-- 3 leviers de contrôle :
--   1. MODEL ALLOWLIST   → quels modèles existent dans le compte
--   2. MODEL RBAC        → quels rôles peuvent appeler quels modèles
--   3. CROSS-REGION      → dans quelles régions l'inférence peut tourner
--
-- Pré-requis : Module 2A exécuté
-- ============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WORKSHOP_WH;

-- ════════════════════════════════════════════════════════════
-- A. MODEL ALLOWLIST — QUELS MODÈLES SONT DISPONIBLES
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST' IN ACCOUNT;

SELECT SNOWFLAKE.CORTEX.COMPLETE(
  'mistral-large2',
  'Dis bonjour en français, en une seule phrase.'
) AS TEST_MODELE_DISPONIBLE;

-- ════════════════════════════════════════════════════════════
-- B. RESTRICTION DE L'ALLOWLIST (DÉMONSTRATION COMMENTÉE)
-- ════════════════════════════════════════════════════════════
--
-- ⚠️  NE PAS EXÉCUTER pendant le workshop — cela coupe l'accès
-- aux modèles pour TOUT le compte (y compris Cortex Code).
--
-- ┌──────────────────────────────────────────────────────────┐
-- │ TEST À FAIRE (sur un compte de test dédié) :            │
-- │                                                         │
-- │   ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST              │
-- │     = 'mistral-large2';                                  │
-- │                                                         │
-- │ RÉSULTAT ATTENDU :                                       │
-- │   • COMPLETE('mistral-large2', ...) → ✅ fonctionne      │
-- │   • COMPLETE('llama3.1-70b', ...)   → ❌ erreur :        │
-- │     "Unknown model llama3.1-70b"                         │
-- │                                                         │
-- │ CE QU'ON DÉMONTRE :                                      │
-- │   L'allowlist est un filtre au niveau COMPTE.            │
-- │   Seuls les modèles listés peuvent être appelés.         │
-- │   Tout le reste est invisible, comme s'il n'existait     │
-- │   pas. C'est le premier niveau de gouvernance AI.        │
-- │                                                         │
-- │ BONNE PRATIQUE :                                         │
-- │   En production, positionner l'allowlist sur les         │
-- │   modèles validés par l'équipe sécurité :               │
-- │     ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST             │
-- │       = 'mistral-large2,llama3.1-70b';                   │
-- │                                                         │
-- │ RESTAURER APRÈS :                                        │
-- │   ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'ALL';     │
-- └──────────────────────────────────────────────────────────┘

-- ════════════════════════════════════════════════════════════
-- C. MODEL RBAC — CONTRÔLE PAR RÔLE (APPLICATION ROLES)
-- ════════════════════════════════════════════════════════════
--
-- L'allowlist (section B) contrôle quels modèles EXISTENT
-- dans le compte. Le RBAC contrôle quels RÔLES peuvent les
-- appeler. Ce sont deux niveaux complémentaires.

SHOW APPLICATION ROLES IN APPLICATION SNOWFLAKE;

-- Le rôle clé : CORTEX_MODELS_ADMIN
-- Seul ce rôle (et ses parents) peut modifier l'allowlist
-- et gérer l'accès aux modèles.

SHOW GRANTS OF APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN;

-- ┌──────────────────────────────────────────────────────────┐
-- │ BONNE PRATIQUE : LEAST PRIVILEGE POUR L'AI               │
-- │                                                         │
-- │ 1. Allowlist = NONE au niveau compte                     │
-- │    ALTER ACCOUNT SET CORTEX_MODELS_ALLOWLIST = 'NONE';   │
-- │    → Plus aucun modèle n'est appelable par défaut.       │
-- │                                                         │
-- │ 2. Autoriser modèle par modèle pour les rôles métier    │
-- │    GRANT APPLICATION ROLE SNOWFLAKE.CORTEX_MODELS_ADMIN  │
-- │      TO ROLE SECURITY_ADMIN;                             │
-- │                                                         │
-- │ 3. Combinaison allowlist + RBAC :                        │
-- │    • Allowlist = 'mistral-large2,llama3.1-70b'           │
-- │      (seuls ces 2 modèles existent dans le compte)       │
-- │    • CORTEX_MODELS_ADMIN → SECURITY_ADMIN                │
-- │      (seul SECURITY_ADMIN peut gérer la liste)           │
-- │    • DATA_ANALYST / DATA_ENGINEER héritent l'accès       │
-- │      aux modèles via la hiérarchie de rôles, mais ne     │
-- │      peuvent PAS modifier l'allowlist.                   │
-- │                                                         │
-- │ CE QU'ON DÉMONTRE :                                      │
-- │   Double verrou : l'allowlist dit "quoi", le RBAC dit    │
-- │   "qui". Un DATA_ANALYST peut appeler mistral-large2     │
-- │   si le modèle est dans l'allowlist, mais ne peut pas    │
-- │   ajouter gpt-4o à la liste.                             │
-- └──────────────────────────────────────────────────────────┘

-- ════════════════════════════════════════════════════════════
-- D. CORTEX_ENABLED_CROSS_REGION — CONTRÔLE GÉOGRAPHIQUE
-- ════════════════════════════════════════════════════════════
--
-- Troisième levier : OÙ l'inférence peut s'exécuter.
-- Certains modèles ne sont pas hébergés dans toutes les
-- régions. Ce paramètre contrôle si Snowflake peut router
-- une requête vers une autre région que celle du compte.

SELECT CURRENT_REGION() AS REGION_ACTUELLE;

SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION' IN ACCOUNT;

-- ┌──────────────────────────────────────────────────────────┐
-- │ VALEURS POSSIBLES ET CONSÉQUENCES                        │
-- │                                                         │
-- │ DISABLED                                                 │
-- │   Inférence uniquement dans la région du compte.         │
-- │   Notre compte est sur AWS eu-central-1 (Francfort).     │
-- │   → Seuls les modèles déployés localement fonctionnent. │
-- │   → Les modèles hébergés dans d'autres régions AWS       │
-- │     ou sur Azure/GCP deviennent inaccessibles.           │
-- │                                                         │
-- │ AWS_EU                                                   │
-- │   Inférence autorisée sur toutes les régions AWS Europe. │
-- │   → Modèles Mistral, Llama, DeepSeek : ✅               │
-- │     (hébergés sur infrastructure AWS)                    │
-- │   → Modèles OpenAI (GPT-4o, o1) : ❌                    │
-- │     (hébergés sur Azure — pas dans le périmètre AWS_EU) │
-- │   → C'est le réglage recommandé RGPD : les données      │
-- │     restent dans l'infrastructure AWS européenne.         │
-- │                                                         │
-- │ AZURE_EU                                                 │
-- │   Inférence autorisée sur toutes les régions Azure EU.   │
-- │   → Un compte Snowflake sur Azure pourrait appeler       │
-- │     GPT-4o (Azure-hosted) mais PAS Anthropic Claude      │
-- │     ni Mistral (AWS-hosted).                             │
-- │                                                         │
-- │ ANY_REGION (valeur actuelle)                              │
-- │   Aucune restriction géographique.                       │
-- │   → Tous les modèles disponibles, toutes les régions.   │
-- │   → ⚠️  Les données peuvent transiter hors UE !          │
-- └──────────────────────────────────────────────────────────┘

-- ┌──────────────────────────────────────────────────────────┐
-- │ TEST À FAIRE (sur un compte de test dédié) :            │
-- │                                                         │
-- │   ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION          │
-- │     = 'AWS_EU';                                          │
-- │                                                         │
-- │ RÉSULTAT ATTENDU :                                       │
-- │   • COMPLETE('mistral-large2', ...) → ✅ fonctionne      │
-- │     (Mistral = AWS, région EU compatible)                │
-- │   • COMPLETE('llama3.1-70b', ...)   → ✅ fonctionne      │
-- │     (Llama = AWS, région EU compatible)                  │
-- │   • COMPLETE('gpt-4o', ...)         → ❌ erreur :        │
-- │     "Model gpt-4o is unavailable"                        │
-- │     (OpenAI = Azure, hors périmètre AWS_EU)             │
-- │                                                         │
-- │ PUIS :                                                   │
-- │   ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION          │
-- │     = 'DISABLED';                                        │
-- │                                                         │
-- │ RÉSULTAT ATTENDU :                                       │
-- │   Seuls les modèles déployés DANS eu-central-1           │
-- │   fonctionnent. Les modèles cross-region échouent.      │
-- │                                                         │
-- │ CE QU'ON DÉMONTRE :                                      │
-- │   La souveraineté des données s'étend à l'inférence AI. │
-- │   Avec AWS_EU, vous garantissez que vos prompts et       │
-- │   vos données ne quittent JAMAIS l'infrastructure AWS    │
-- │   européenne — même quand Snowflake route vers une       │
-- │   autre région pour l'inférence.                         │
-- │                                                         │
-- │   Pour un client dans la finance ou la santé, c'est la  │
-- │   réponse à : "Où partent mes données quand j'appelle   │
-- │   un LLM ?"                                              │
-- │                                                         │
-- │ RESTAURER APRÈS :                                        │
-- │   ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION          │
-- │     = 'ANY_REGION';                                      │
-- └──────────────────────────────────────────────────────────┘

-- ════════════════════════════════════════════════════════════
-- E. RÉCAPITULATIF — LES 3 LEVIERS
-- ════════════════════════════════════════════════════════════
--
-- ┌─────────────────────┬────────────────────┬──────────────┐
-- │ Levier              │ Contrôle           │ Granularité  │
-- ├─────────────────────┼────────────────────┼──────────────┤
-- │ MODELS_ALLOWLIST    │ Quels modèles      │ Compte       │
-- │ APPLICATION ROLES   │ Qui peut gérer     │ Rôle         │
-- │ CROSS_REGION        │ Où tourne l'infér. │ Compte       │
-- └─────────────────────┴────────────────────┴──────────────┘

-- ════════════════════════════════════════════════════════════
-- F. LIMITES BUDGÉTAIRES CORTEX
-- ════════════════════════════════════════════════════════════

SHOW PARAMETERS LIKE 'CORTEX_CODE%' IN ACCOUNT;

-- Pour limiter l'utilisation AI par utilisateur :
-- ALTER USER <username> SET CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER = 5;
