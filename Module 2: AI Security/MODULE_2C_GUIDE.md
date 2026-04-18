# MODULE 2C — AI_REDACT & Contrôles probabilistes

## Guide instructeur

### Objectif
Combler le fossé entre le masking par colonne (déterministe) et la protection du texte libre (probabiliste). AI_REDACT détecte et masque les PII dans du texte non structuré — là où le masking traditionnel ne peut pas aider.

### Durée : 15 min

### Script : `03_ai_redact_demo.sql`

### Structure

| Acte | Temps | Contenu |
|------|-------|---------|
| 1. Données brutes | 2 min | Transcriptions support client avec PII mélangées dans du texte libre |
| 2. AI_REDACT | 5 min | Redaction complète, mode detect, catégories sélectives |
| 3. Pipeline | 3 min | AI_REDACT → AI_SENTIMENT (analyse sécurisée) |
| 4. Masking policy + AI_REDACT | 5 min | Pattern ultime : AI_REDACT dans une masking policy dynamique |

### Points d'enseignement

1. **Le fossé** : Le masking par colonne protège les colonnes structurées. Mais quand un client dit "Mon numéro de sécu est 1 85 12 75..." dans un champ texte libre, le masking ne peut rien faire. AI_REDACT comble ce fossé.

2. **3 modes d'AI_REDACT** :
   - `redact` (défaut) : remplace les PII par `[CATEGORIE]`
   - `detect` : retourne les spans JSON avec catégorie, texte, positions — pour l'audit
   - Catégories sélectives : ne masquer que NAME + EMAIL, ou que NATIONAL_ID + PAYMENT_CARD_DATA

3. **Pattern pipeline** : `AI_REDACT → CREATE TABLE → AI_SENTIMENT`. Le modèle d'analyse ne voit JAMAIS les PII. C'est comme ça qu'on construit des pipelines AI conformes.

4. **Pattern masking policy** (Acte 4) : C'est le moment "wow". On met AI_REDACT DANS une masking policy. Les rôles privilégiés voient le texte brut ; tous les autres voient le texte automatiquement redacté. Gouvernance dynamique alimentée par l'AI.

5. **Déterministe vs Probabiliste** :
   - Déterministe (masking, RAP, projection) = murs, 100% fiable
   - Probabiliste (AI_REDACT, GUARD) = filets de sécurité, très bon mais pas parfait
   - En production, on veut les DEUX : ceintures ET airbags

### ⚠️ Pièges

- **CORTEX.GUARD** n'est PAS disponible sur eu-central-1. Ne pas essayer de le démontrer.
- **AI_REDACT latence** : ~5-15 sec par appel. Les requêtes avec 5 transcriptions prennent du temps.
- **SECURITY_WORKSHOP database** : créée par le script, supprimée à la fin. Si le script plante avant le nettoyage, `DROP DATABASE SECURITY_WORKSHOP` pour nettoyer.
- **Le script utilise des données françaises** mais avec quelques éléments anglais (noms internationaux dans les transcriptions) — c'est volontaire pour un scénario multinational réaliste.
- **Le nettoyage supprime TOUT** y compris la database. Pas d'impact sur les VOLTAIRE_* databases.

### Transition vers 2E
« On a les contrôles déterministes (masking, RAP, projection) ET les contrôles probabilistes (AI_REDACT). Mais gouverner sans surveiller, c'est construire une porte sans vérifier si quelqu'un passe. Il nous manque le monitoring. »

### Certification
- **D4.4** : AI Redact, probabilistic controls