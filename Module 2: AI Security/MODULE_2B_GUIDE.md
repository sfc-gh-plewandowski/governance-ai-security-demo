# MODULE 2B — Gouvernance des capacités (Dimension 2)

## Guide instructeur

### Objectif
Démontrer le contrôle granulaire de l'accès AI : quel RÔLE peut utiliser quel MODÈLE (Model RBAC), quelle FONCTIONNALITÉ Cortex (Feature Access), et le privilège global USE AI FUNCTIONS. C'est le cœur de la Dimension 2.

### Durée : 20 min

### Script : `02_capability_governance.sql`

### Structure

| Section | Temps | Contenu |
|---------|-------|---------|
| Acte 1 — Model RBAC | 10 min | `CORTEX_BASE_MODELS_REFRESH`, application roles par modèle, ALLOWLIST=None + grants, tests cross-rôle |
| Acte 2 — Feature Access | 5 min | 5 database roles, segmentation par fonctionnalité (functions vs agents vs embed) |
| Acte 3 — LLM Privileges | 5 min | `USE AI FUNCTIONS ON ACCOUNT`, interrupteur global, combo avec database roles |

### Points d'enseignement

1. **Model RBAC (GA avril 2025)** : Chaque modèle a un rôle applicatif `SNOWFLAKE."CORTEX-MODEL-ROLE-<MODELE>"`. La best practice production est `ALLOWLIST = 'None'` + grants individuels. C'est du least privilege appliqué à l'AI.

2. **`CORTEX_BASE_MODELS_REFRESH()`** : OBLIGATOIRE une première fois pour activer les ~69 rôles par modèle. Sans cet appel, seul `CORTEX_MODELS_ADMIN` existe.

3. **Fonctions managées et alias modèle** : AI_TRANSLATE utilise `arctic-translate`, AI_SENTIMENT utilise `arctic-sentiment`, SUMMARIZE utilise `mistral-7b`, CLASSIFY_TEXT/AI_REDACT utilisent `llama3.1-70b`. Pour autoriser AI_TRANSLATE, il faut le rôle `CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE`.

4. **Feature Access** : 5 database roles dans SNOWFLAKE. CORTEX_USER est accordé à PUBLIC par défaut (tout le monde a accès). En production, retirer CORTEX_USER de PUBLIC et accorder AI_FUNCTIONS_USER, CORTEX_AGENT_USER, CORTEX_EMBED_USER, etc. selon le besoin.

5. **USE AI FUNCTIONS ON ACCOUNT** : Privilège de niveau COMPTE, distinct des database roles. Par défaut accordé à PUBLIC. Un utilisateur a besoin des DEUX pour appeler une fonction AI : (1) USE AI FUNCTIONS et (2) un database role (CORTEX_USER ou AI_FUNCTIONS_USER). Si l'un manque → bloqué. C'est un interrupteur global ON/OFF. En production, révoquer de PUBLIC et accorder rôle par rôle pour un contrôle total.

6. **3 couches de contrôle (Acte 1 + 2 + 3)** : Model RBAC (quel modèle) + Feature Access (quelle feature) + USE AI FUNCTIONS (interrupteur global) = défense en profondeur. Chaque couche est indépendante et gérée par ACCOUNTADMIN.

### ⚠️ Pièges

- **ALLOWLIST = 'None'** bloque TOUT sauf les rôles applicatifs. Si on oublie de donner les grants, personne ne peut utiliser Cortex.
- **Toujours restaurer ALLOWLIST = 'ALL'**, **CORTEX_USER → PUBLIC**, et **USE AI FUNCTIONS → PUBLIC** à la fin. Sinon les modules suivants cassent.
- **BCR-2220** (bundle 2026_02, activé par défaut avril 2026) : étend le Model RBAC à TOUTES les fonctions Cortex AI, pas seulement COMPLETE. Mentionner en passant.
- **Le REVOKE est symétrique** : chaque GRANT doit avoir son REVOKE dans le nettoyage.
- **USE AI FUNCTIONS ne s'applique PAS** aux fonctions AI appelées depuis des Native Apps — mentionner cette exception si la question est posée.

### Transition vers 2C
« On a les 3 niveaux de contrôle : compte (cross-region, allowlist, USE AI FUNCTIONS), rôle×modèle (Model RBAC), rôle×feature (Feature Access). Maintenant on passe aux contrôles probabilistes — AI_REDACT pour la protection PII dans le texte libre. »

### Certification
- **D4.2** : Model allowlist, application roles, feature access, LLM privileges
