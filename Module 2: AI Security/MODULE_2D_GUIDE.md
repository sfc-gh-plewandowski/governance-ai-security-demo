# MODULE 2D — Monitoring & Audit AI

## Guide instructeur

### Objectif
Fermer la boucle de gouvernance : classify → protect → use → **MONITOR** → refine. Démontrer les 3 niveaux de monitoring Cortex AI et les contrôles budgétaires.

### Durée : 15 min

### Script : `04_ai_monitoring.sql`

### Structure

| Acte | Temps | Contenu |
|------|-------|---------|
| 1. Audit détaillé | 5 min | 3 vues d'audit (AISQL, AI_FUNCTIONS, QUERY_HISTORY) |
| 2. Consommation | 4 min | Coût par modèle, par utilisateur, vue de facturation |
| 3. Anomalies | 3 min | Spike detection, hors heures, modèles coûteux |
| 4. Budget | 3 min | CORTEX_CODE budget limits par utilisateur |

### Points d'enseignement

1. **3 niveaux de monitoring** :
   - `CORTEX_AISQL_USAGE_HISTORY` : détail par appel (tokens, credits, user_id, query_id)
   - `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` : enrichi avec ROLE_NAMES — essentiel pour l'audit RBAC
   - `QUERY_HISTORY` : temps réel (~0 latence vs ~2h pour ACCOUNT_USAGE)

2. **QUERY_HISTORY pour les démos live** : En workshop, `ACCOUNT_USAGE` peut ne pas avoir les données des dernières 2h. `QUERY_HISTORY` avec `ILIKE '%CORTEX%COMPLETE%'` montre les appels faits il y a 5 minutes.

3. **Patterns de détection** :
   - **Spike** : > 50 appels/heure par utilisateur → anomalie potentielle
   - **Hors heures** : appels entre 20h et 7h → possible exfiltration via AI
   - **Modèles coûteux** : deepseek-r1 consomme significativement plus que mistral-7b

4. **Budget Cortex Code** : `CORTEX_CODE_CLI_DAILY_EST_CREDIT_LIMIT_PER_USER` et `CORTEX_CODE_SNOWSIGHT_DAILY_EST_CREDIT_LIMIT_PER_USER`. Valeur -1 = illimité, 0 = désactivé.

5. **Boucle complète** : La gouvernance AI n'est pas un état, c'est un processus cyclique. Le monitoring alimente le raffinement : si on détecte un pattern anormal, on ajuste les policies. C'est la Dimension 3 en action.

### ⚠️ Pièges

- **Latence ACCOUNT_USAGE** : ~2h. Les appels Cortex faits pendant le workshop ne seront PAS visibles dans CORTEX_AISQL_USAGE_HISTORY ou CORTEX_AI_FUNCTIONS_USAGE_HISTORY. Utiliser QUERY_HISTORY pour la démo live.
- **METERING_DAILY_HISTORY** peut être vide si le compte est nouveau ou si les appels Cortex n'ont pas encore été facturés.
- **Les budgets ne s'appliquent qu'à Cortex Code** (CLI et Snowsight), pas aux appels CORTEX.COMPLETE directs. Mentionner cette limitation.
- **USER_ID → NAME** : CORTEX_AISQL_USAGE_HISTORY a USER_ID, pas USER_NAME. Le JOIN avec USERS est nécessaire.

### Vues Cortex disponibles (pour référence)

| Vue | Contenu |
|-----|---------|
| `CORTEX_AISQL_USAGE_HISTORY` | Appels AI SQL (COMPLETE, TRANSLATE, etc.) |
| `CORTEX_AI_FUNCTIONS_USAGE_HISTORY` | Idem + ROLE_NAMES |
| `CORTEX_AGENT_USAGE_HISTORY` | Appels Cortex Agents |
| `CORTEX_CODE_CLI_USAGE_HISTORY` | Utilisation Cortex Code CLI |
| `CORTEX_CODE_SNOWSIGHT_USAGE_HISTORY` | Utilisation Cortex Code Snowsight |
| `CORTEX_ANALYST_USAGE_HISTORY` | Cortex Analyst |
| `CORTEX_SEARCH_SERVING_USAGE_HISTORY` | Cortex Search |
| `METERING_DAILY_HISTORY` | Facturation globale par service |

### Transition vers Wrap-up
« On a couvert les 3 dimensions : gouverner les données, gouverner les capacités, gouverner le contexte. La gouvernance n'est pas héritée — elle est résolue à chaque requête, y compris les requêtes AI. C'est ce que vous pouvez maintenant démontrer à n'importe quel RSSI. »

### Certification
- **D5.2** : AI Monitoring, audit
