# Module 2B — Gouvernance des Capacités (Dimension 2)

## Overview

Dimension 2 : on ne contrôle pas seulement les DONNÉES, on contrôle les CAPACITÉS AI elles-mêmes. Ce module montre 5 leviers de contrôle : cross-region, model allowlist, model RBAC (per-model application roles), feature access by role (database roles), et budget limits.

> **Le message central** : Un RSSI ne veut pas juste savoir que les données sont protégées. Il veut savoir quels modèles sont accessibles, qui les utilise, où ils tournent, et quelles features AI sont activées par rôle.

## Position in the Day

| Info | Detail |
|------|--------|
| **Position** | Deuxième module AI (après 2A) |
| **Durée** | ~25 minutes |
| **Dimension** | **Dimension 2 — Capability Governance** |
| **Prérequis** | Module 2A |

> **[CERTIFICATION: D4.2]** Ce module couvre D4.2 : "Model allowlist, cross-region inference, model RBAC, feature access control, cost controls".

---

## Ordre d'exécution

| # | Fichier | Durée | Résumé |
|---|---------|-------|--------|
| 1 | `02_capability_governance.sql` | 25 min | 5 leviers : cross-region, allowlist, model RBAC, feature access, budget |

---

## Teacher's Notes

### Script 02 — Capability Governance (25 min)

#### TELL (before — 3 min)

**[A DIRE]** : *"Dimension 2 : qui peut utiliser quel modèle, quelle feature AI ? En production, vous ne voulez pas que tout le monde ait accès à tous les modèles. Un modèle plus puissant = plus de risque d'extraction de données = plus cher. On va voir 5 leviers de contrôle, du plus large au plus fin."*

Les 5 leviers :
1. **Cross-Region** — où les modèles s'exécutent physiquement (mTLS)
2. **Model Allowlist** — quels modèles existent sur le compte
3. **Model RBAC** — quel rôle peut utiliser quel modèle (per-model application roles)
4. **Feature Access** — quel rôle peut utiliser quelle feature Cortex (database roles)
5. **Budget Limits** — combien chaque utilisateur peut consommer

#### SHOW (do-together — 18 min)

##### Section 0 — Inventaire (2 min)

- Exécuter `CORTEX_BASE_MODELS_REFRESH()` — **expliquer que c'est cette procédure qui active les application roles per-model**
- `SHOW MODELS IN SNOWFLAKE.MODELS` — montrer les 68 modèles disponibles
- `CURRENT_REGION()` = `AWS_EU_CENTRAL_1` (Francfort)
- Test rapide avec mistral-large2

##### Section 1 — Cross-Region (3 min)

- `SHOW PARAMETERS LIKE 'CORTEX_ENABLED_CROSS_REGION'` — montrer la valeur actuelle
- **Démo live** : `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'AWS_EU'`
- Tester mistral-large2 et llama (AWS → ✅), expliquer que les modèles Azure (OpenAI GPT) seraient bloqués
- **Expliquer** : le transit inter-régions utilise mTLS. Avec AWS_EU, les prompts ne quittent jamais l'infrastructure AWS européenne
- **Remettre à ANY_REGION immédiatement**
- Doc : https://docs.snowflake.com/en/sql-reference/parameters#label-cortex-enable-cross-region

##### Section 2 — Model Allowlist (3 min)

- `SHOW PARAMETERS LIKE 'CORTEX_MODELS_ALLOWLIST'` — montrer `ALL`
- **Démo live** : restreindre à `'mistral-large2'` seul
- Tester : mistral-large2 ✅, llama3.1-70b ❌ ("Unknown model")
- **Remettre à ALL immédiatement**
- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#label-cortex-llm-allowlist

##### Section 3 — Model RBAC (6 min) ⭐ Section principale

- `SHOW APPLICATION ROLES LIKE '%CORTEX-MODEL%'` — montrer les 69 rôles per-model
- Expliquer le naming : `CORTEX-MODEL-ROLE-<MODELE>` + `CORTEX-MODEL-ROLE-ALL`
- **Démo live best practice** :
  1. `ALLOWLIST = 'None'` — couper l'accès global
  2. Grants ciblés : DATA_ANALYST → mistral-large2 + fonctions managées, DATA_ENGINEER → +llama+deepseek, SECURITY_ADMIN → ALL
  3. **Role-switching** : `USE ROLE DATA_ANALYST` → test ✅/❌, `USE ROLE DATA_ENGINEER` → test ✅, `USE ROLE SECURITY_ADMIN` → test ✅
- **[A DIRE]** : *"Les fonctions managées comme AI_TRANSLATE utilisent des modèles internes (arctic-translate). Il faut aussi autoriser ces modèles-là, sinon TRANSLATE casse même si COMPLETE marche."*
- **Cleanup** : révoquer tous les grants, remettre ALLOWLIST = ALL
- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#label-cortex-llm-rbac

##### Section 4 — Feature Access by Role (3 min)

- 5 database roles Cortex :
  - `CORTEX_USER` → accès complet (granted to PUBLIC par défaut)
  - `AI_FUNCTIONS_USER` → fonctions AI scalaires uniquement (GA avril 2026)
  - `CORTEX_AGENT_USER` → Cortex Agents API uniquement
  - `CORTEX_EMBED_USER` → fonctions d'embedding uniquement
  - `COPILOT_USER` → Cortex Code dans Snowsight (granted to PUBLIC par défaut)
- **Démo live** :
  1. `REVOKE DATABASE ROLE SNOWFLAKE.CORTEX_USER FROM ROLE PUBLIC` — couper l'accès global
  2. DATA_ANALYST → AI_FUNCTIONS_USER, DATA_ENGINEER → AI_FUNCTIONS_USER + CORTEX_AGENT_USER, SECURITY_ADMIN → CORTEX_USER
  3. Test : `USE ROLE DATA_ANALYST` → COMPLETE ✅
- **[A DIRE]** : *"La différence avec le Model RBAC : ici on contrôle l'accès à la FEATURE (COMPLETE, agents, embeddings), pas au modèle spécifique. Les deux se combinent."*
- **Cleanup** : révoquer, remettre CORTEX_USER to PUBLIC
- Doc : https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql#cortex-llm-privileges

##### Section 5-6 — Budget + Audit (1 min)

- Budget limits : `CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER`
- Audit query : `CORTEX_AISQL_USAGE_HISTORY` — montrer qui a utilisé quels modèles

#### TELL (after — 4 min)

**[A DIRE]** : *"5 leviers, du plus large au plus fin : géo (cross-region), modèles dispo (allowlist), accès par rôle×modèle (RBAC), accès par rôle×feature (database roles), budget. Ces 5 leviers se combinent. C'est ce que le RSSI veut voir dans votre rapport de posture sécurité AI. Maintenant, la question clé : est-ce que la gouvernance du matin — les masking policies, les RAP — se transmet quand on utilise l'AI ?"*

---

## Pièges courants

| Piège | Explication |
|-------|-------------|
| Oublier de remettre ALL / ANY_REGION après chaque démo | Les participants ne pourront plus utiliser COMPLETE dans les modules suivants |
| Ne pas exécuter CORTEX_BASE_MODELS_REFRESH() | Les application roles per-model n'apparaîtront pas sans le refresh |
| Confondre Model RBAC et Feature Access | Model RBAC = quel modèle (via application roles). Feature Access = quelle feature Cortex (via database roles). Les deux se combinent. |
| Oublier les modèles des fonctions managées | AI_TRANSLATE utilise arctic-translate, SUMMARIZE utilise mistral-7b. Il faut accorder ces model roles aussi. |
| Penser que CORTEX_CODE limits = usage AI global | Les limits CORTEX_CODE sont spécifiques à Cortex Code (CoCo), pas à COMPLETE |

---

## Fichiers du module

```
Module 2: AI Security/
├── 02_capability_governance.sql   5 leviers de gouvernance AI
└── MODULE_2B_GUIDE.md             Ce fichier
```
