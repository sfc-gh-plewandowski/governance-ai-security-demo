# MODULE 2B — Gouvernance des capacités (Dimension 2)

## Guide instructeur

### Objectif
Démontrer le contrôle granulaire de l'accès AI : quel RÔLE peut utiliser quel MODÈLE (Model RBAC) et quelle FONCTIONNALITÉ Cortex (Feature Access). C'est le cœur de la Dimension 2.

### Durée : 15 min

### Script : `02_capability_governance.sql`

### Structure

| Section | Temps | Contenu |
|---------|-------|---------|
| Acte 1 — Model RBAC | 10 min | `CORTEX_BASE_MODELS_REFRESH`, application roles par modèle, ALLOWLIST=None + grants, tests cross-rôle |
| Acte 2 — Feature Access | 5 min | 5 database roles, segmentation par fonctionnalité (functions vs agents vs embed) |

### Points d'enseignement

1. **Model RBAC (GA avril 2025)** : Chaque modèle a un rôle applicatif `SNOWFLAKE."CORTEX-MODEL-ROLE-<MODELE>"`. La best practice production est `ALLOWLIST = 'None'` + grants individuels. C'est du least privilege appliqué à l'AI.

2. **`CORTEX_BASE_MODELS_REFRESH()`** : OBLIGATOIRE une première fois pour activer les ~69 rôles par modèle. Sans cet appel, seul `CORTEX_MODELS_ADMIN` existe.

3. **Fonctions managées et alias modèle** : AI_TRANSLATE utilise `arctic-translate`, AI_SENTIMENT utilise `arctic-sentiment`, SUMMARIZE utilise `mistral-7b`, CLASSIFY_TEXT/AI_REDACT utilisent `llama3.1-70b`. Pour autoriser AI_TRANSLATE, il faut le rôle `CORTEX-MODEL-ROLE-ARCTIC-TRANSLATE`.

4. **Feature Access** : 5 database roles dans SNOWFLAKE. CORTEX_USER est accordé à PUBLIC par défaut (tout le monde a accès). En production, retirer CORTEX_USER de PUBLIC et accorder AI_FUNCTIONS_USER, CORTEX_AGENT_USER, etc. selon le besoin.

5. **Combinaison** : Model RBAC + Feature Access = matrice d'accès complète. Un analyste peut avoir AI_FUNCTIONS_USER (features scalaires) + 3 modèles spécifiques. Un engineer peut avoir + CORTEX_AGENT_USER + deepseek-r1 pour le raisonnement.

### ⚠️ Pièges

- **ALLOWLIST = 'None'** bloque TOUT sauf les rôles applicatifs. Si on oublie de donner les grants, personne ne peut utiliser Cortex.
- **Toujours restaurer ALLOWLIST = 'ALL'** et **CORTEX_USER → PUBLIC** à la fin. Sinon les modules suivants cassent.
- **BCR-2220** (bundle 2026_02, activé par défaut avril 2026) : étend le Model RBAC à TOUTES les fonctions Cortex AI, pas seulement COMPLETE. Mentionner en passant.
- **Le REVOKE est symétrique** : chaque GRANT doit avoir son REVOKE dans le nettoyage.

### Transition vers 2C
« On a les 3 niveaux de contrôle : compte (cross-region, allowlist), rôle×modèle (Model RBAC), rôle×feature (Feature Access). Maintenant on PROUVE que la gouvernance du matin — masking, RAP, projection — se transmet à l'AI. »

### Certification
- **D4.2** : Model allowlist, application roles, cross-region
