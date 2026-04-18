# MODULE 2C — La preuve : la gouvernance se transmet à l'AI

## Guide instructeur

### Objectif
C'est LE moment de l'après-midi. 4 preuves formelles que TOUT ce qu'on a construit le matin (masking, RAP, projection) est respecté quand Cortex AI interroge les données. Réponse définitive à la question du RSSI.

### Durée : 25 min

### Script : `03_governance_carry_forward.sql`

### Structure

| Preuve | Temps | Ce qu'elle démontre | Rôles comparés |
|--------|-------|---------------------|----------------|
| 1. Masking → AI | 7 min | Le modèle reçoit des hash, pas des données réelles | SECURITY_ADMIN vs DATA_ANALYST |
| 2. RAP → AI | 7 min | Le modèle ne connaît que les lignes autorisées | SECURITY_ADMIN (1000) vs DATA_ANALYST (~208) |
| 3. Projection → AI | 4 min | Le modèle ne peut PAS accéder aux colonnes interdites | DATA_ANALYST → erreur projection policy |
| 4. CRM → AI | 7 min | Le masking SIRET se transmet sur un autre domaine | SECURITY_ADMIN vs DATA_ANALYST |

### Points d'enseignement

1. **Preuve 1 — Masking → AI** : On affiche côte à côte les colonnes brutes (PERMIS, IBAN) ET le résumé AI. SECURITY_ADMIN voit le vrai permis dans le résumé ; DATA_ANALYST voit "identifiants hashés". Le modèle ne peut pas deviner les données originales à partir d'un hash SHA2.

2. **Preuve 2 — RAP → AI** : Le modèle ne "connaît" que les lignes qu'il peut voir. SECURITY_ADMIN : "1000 employés dans 15 départements". DATA_ANALYST : "~208 employés dans 3 départements". Le modèle ne sait même pas que d'autres départements existent.

3. **Preuve 3 — Projection → AI** : Même CORTEX.COMPLETE ne peut pas contourner une projection policy. La colonne NIR est bloquée au niveau SQL, avant que le modèle n'entre en jeu. Erreur claire : "restricted by a Projection Policy".

4. **Preuve 4 — CRM → AI** : On sort du domaine RH pour prouver que le même comportement s'applique partout. Le masking SIRET fonctionne identiquement sur VOLTAIRE_CRM.

### ⚠️ Pièges

- **`USE SECONDARY ROLES NONE`** au début, **`USE SECONDARY ROLES ALL`** à la fin. CRITIQUE.
- **Preuve 3** : la requête est COMMENTÉE pour éviter une erreur accidentelle. Décommenter pour la démo, puis re-commenter.
- **WHERE EMPLOYE_ID = 1 vs 3** : DATA_ANALYST ne voit pas EMPLOYE_ID=1 (RAP filtre par département). Utiliser EMPLOYE_ID=3 qui est dans un département autorisé pour DATA_ANALYST.
- **Latence CORTEX** : 8 appels COMPLETE dans ce module (~30-60 sec chacun). Prévoir de lancer les requêtes SECURITY_ADMIN et DATA_ANALYST en parallèle dans 2 onglets Snowsight.

### Mise en scène
Ouvrir 2 onglets Snowsight côte à côte : un en SECURITY_ADMIN, un en DATA_ANALYST. Lancer la même requête dans les deux. Laisser les participants comparer visuellement. C'est le moment "aha" qui vend la gouvernance Snowflake.

### Transition vers 2D
« On a prouvé que les contrôles DÉTERMINISTES (masking, RAP, projection) fonctionnent avec l'AI. Mais que faire quand les PII sont dans du texte libre, pas dans des colonnes ? C'est là qu'interviennent les contrôles PROBABILISTES. »

### Certification
- **D4.3** : Governance carry-forward to AI
