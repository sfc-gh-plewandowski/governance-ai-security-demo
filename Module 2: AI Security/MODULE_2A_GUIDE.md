# MODULE 2A — Flux d'inférence AI & Frontière de confiance

## Guide instructeur

### Objectif
Poser les fondations de l'après-midi : comprendre OÙ l'inférence s'exécute, QUELS modèles sont disponibles, et PROUVER que la gouvernance du matin s'applique avant que le modèle ne voie les données.

### Durée : 20 min

### Script : `01_inference_flow.sql`

### Structure

| Section | Temps | Contenu |
|---------|-------|---------|
| A. Cross-Region | 5 min | `CORTEX_ENABLED_CROSS_REGION` — géographie de l'inférence, impact RGPD |
| B. Model Allowlist | 5 min | `CORTEX_MODELS_ALLOWLIST` — restriction/autorisation de modèles au niveau compte |
| C. Premier appel | 2 min | `CORTEX.COMPLETE` — vérifier que tout fonctionne |
| D. Le Pont | 8 min | Même requête AI, 2 rôles → 2 résultats (bridge vers Module 2C) |

### Points d'enseignement

1. **Cross-Region & RGPD** : `AWS_EU` garantit que l'inférence reste en Europe. Si le compte est en eu-central-1, les données ne quittent jamais l'UE avec `AWS_EU`. Mentionner le mTLS entre régions.

2. **Allowlist = premier filtre** : Même si un rôle a les droits sur un modèle, si le modèle n'est pas dans l'allowlist, il est bloqué. C'est un contrôle au niveau compte, pas au niveau rôle.

3. **Le Pont** : C'est le moment "aha". Le modèle reçoit des hash SHA2 quand DATA_ANALYST l'utilise — il ne peut PAS deviner les données originales. Ce n'est PAS un aperçu de 2C (qui fait 4 preuves formelles), c'est la démonstration que l'architecture de gouvernance est fondamentalement correcte.

### ⚠️ Pièges

- **`USE SECONDARY ROLES NONE`** : OBLIGATOIRE avant le test cross-rôle. Sans ça, toutes les roles sont actifs et le masking semble cassé.
- **Restaurer ALLOWLIST = ALL** après la démo allowlist. Sinon les modules suivants cassent.
- **Restaurer CROSS_REGION = ANY_REGION** après la démo cross-region.
- **Latence Cortex** : 10–60 secondes par appel COMPLETE, prévenir les participants.

### Transition vers 2B
« On vient de voir les contrôles au niveau COMPTE — où et quels modèles. Maintenant on descend au niveau RÔLE : qui utilise quel modèle, et quelle fonctionnalité Cortex. »

### Certification
- **D4.1** : Inference flow, trust boundary
