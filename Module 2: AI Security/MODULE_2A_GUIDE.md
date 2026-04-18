# MODULE 2A — Flux d'inférence AI & Frontière de confiance

## Guide instructeur

### Qu'est-ce qu'une inférence ?
Une **inférence** est le processus par lequel un modèle AI génère une réponse à partir d'une entrée (prompt) — c'est le moment où le modèle « réfléchit ». **Exécuter une inférence** dans Snowflake signifie envoyer des données et un prompt à un modèle Cortex (via `CORTEX.COMPLETE`) et recevoir la réponse générée.

### Objectif
Poser les fondations de l'après-midi : comprendre OÙ l'inférence s'exécute, QUELS modèles sont disponibles, et PROUVER que la gouvernance s'applique avant que le modèle ne voie les données — aussi bien le masking (colonnes) que la RAP (lignes/domaines).

### Durée : 20 min

### Script : `01_inference_flow.sql`

### Structure

| Section | Temps | Contenu |
|---------|-------|---------|
| A. Cross-Region | 4 min | `CORTEX_ENABLED_CROSS_REGION` — géographie de l'inférence, impact RGPD |
| B. Model Allowlist | 4 min | `CORTEX_MODELS_ALLOWLIST` — restriction/autorisation de modèles au niveau compte |
| C. Masking → AI | 6 min | Même profil employé, 2 rôles → le modèle reçoit hash ou données en clair |
| D. RAP → AI | 6 min | Le modèle ne connaît que les départements/domaines autorisés par le rôle |

### Points d'enseignement

1. **Cross-Region & RGPD** : `AWS_EU` garantit que l'inférence reste en Europe. Si le compte est en eu-central-1, les données ne quittent jamais l'UE avec `AWS_EU`. Mentionner le mTLS entre régions.

2. **Allowlist = premier filtre** : Même si un rôle a les droits sur un modèle, si le modèle n'est pas dans l'allowlist, il est bloqué. C'est un contrôle au niveau compte, pas au niveau rôle.

3. **Masking → AI** (section C) : Le modèle reçoit des hash SHA2 quand DATA_ANALYST l'utilise — il ne peut PAS deviner les données originales. La gouvernance est appliquée AVANT que le modèle ne voie les données.

4. **RAP → AI** (section D) : Quand DATA_ANALYST demande au modèle des informations sur le département Informatique, le modèle répond « 0 employés » — car la RAP filtre ces lignes avant l'inférence. Le modèle ne sait même pas que ce département existe. C'est la preuve que la RAP ne limite pas seulement les SELECT classiques, mais aussi ce que l'AI peut « savoir ».

   Rappel des domaines par rôle (RAP_DEPARTEMENT) :
   - SECURITY_ADMIN : tous les départements (1000 employés)
   - DATA_ANALYST : Commercial, Marketing, Communication (~208 employés)
   - DATA_ENGINEER : Informatique, R&D, Production (~200 employés)

### ⚠️ Pièges

- **`USE SECONDARY ROLES NONE`** : OBLIGATOIRE avant les tests cross-rôle (sections C et D). Sans ça, toutes les roles sont actifs et le masking/RAP semble cassé.
- **Restaurer ALLOWLIST = ALL** après la démo allowlist (section B). Sinon les modules suivants cassent.
- **Restaurer CROSS_REGION = ANY_REGION** après la démo cross-region (section A).
- **Latence Cortex** : 10–60 secondes par appel COMPLETE, prévenir les participants.
- **EMPLOYE_ID** : en section C, utiliser EMPLOYE_ID=1 pour SECURITY_ADMIN et EMPLOYE_ID=3 pour DATA_ANALYST (l'employé 1 peut ne pas être visible pour DATA_ANALYST selon le département).

### Transition vers 2B
« On vient de voir les contrôles au niveau COMPTE — où et quels modèles — et on a prouvé que masking et RAP s'appliquent avant l'inférence. Maintenant on descend au niveau RÔLE : qui utilise quel modèle, et quelle fonctionnalité Cortex. »

### Certification
- **D4.1** : Inference flow, trust boundary
