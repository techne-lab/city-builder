# Retour sur le prototype — City Builder (Godot 4)

Date: 2026-04-14  
Projet: `citybuilder` (prototype MVP)

## État actuel du jeu (ce qui “tourne”)

### Boucle principale
- **Build**: placement sur **grille 1x1**, preview **vert/rouge**, coût payé à la pose.
- **Produce resources**: bâtiments producteurs via **Timer** (pas de `_process` par bâtiment).
- **Feed population**: consommation de nourriture **par habitant** (interval-based).
- **Earn gold**: génération d’or **par habitant** (interval-based).
- **Expand**: maisons augmentent la capacité de population, stockage augmente les caps.
- **Victoire**: atteinte de **30 population** → message de victoire + blocage du placement.

### Ressources et règles
- Ressources: **wood / food / gold**
- **Food** est la ressource limitante (conso + coût de croissance).
- **Caps** de stockage appliqués (wood/food/gold) + bonus du bâtiment **Storage**.

### Équilibrage (centralisé)
- Toutes les valeurs principales sont regroupées dans **`Data/game_balance.tres`**.
- Les tuning par bâtiment (coût, production, cap pop, bonus storage) sont appliqués au runtime.

### UI actuelle
- Affiche: wood/food/gold, population, bâtiment sélectionné, détails du bâtiment.
- Boutons: House / Farm / Lumber Mill / Storage.
- Overlay debug: **food production/s**, **food consumption/s**, **gold income/s**.

## Points forts (bons choix pour un MVP)
- **Simplicité**: règles lisibles, système modulaire (managers + data).
- **Centralisation du game design**: un point unique pour itérer rapidement.
- **Production sans surcharge**: timers au lieu de `_process` partout.
- **Feedback placement**: preview + petite animation, clair pour itération.

## Limites / risques (si on vise “commercialisable”)

### 1) Profondeur et rejouabilité
Actuellement, la progression est surtout une **course à la capacité** + une optimisation de ratios (farm/house/sawmill).
Pour un produit commercial, il faut:
- **objectifs intermédiaires** (quêtes, milestones, paliers),
- **variété de décisions** (spécialisations, trade-offs durables),
- **contenu** (plus de bâtiments/rôles) et **systèmes** (même simples).

### 2) Lisibilité / UX
Le joueur doit comprendre rapidement:
- pourquoi ça bloque (coûts, caps, manque de food),
- ce qui est rentable et à quel rythme,
- quel est le prochain meilleur pas.
Le HUD actuel est utile pour debug, mais il manque:
- messages contextualisés (“manque 3 gold”),
- surlignage des coûts / ressources manquantes,
- tutoriel léger / onboarding.

### 3) Économie “plate”
L’économie est stable et linéaire:
- pas de variation, pas d’événements, pas de pics/creux intéressants,
- peu d’arbitrage entre court terme et long terme.
Pour un produit, on veut introduire des “pression points” sans softlock.

### 4) “Spam prevention” vs plaisir
Si l’or est trop lent, le jeu devient frustrant.
Si l’or est trop rapide, la décision se résume au spam.
Il faudra calibrer la friction (coûts, temps, caps) pour que:
- le joueur **planifie**, mais **agit souvent**.

## Axes d’amélioration (priorisés)

### A. Court terme (1–2 semaines) — rendre le jeu “jouable sans debug”
- **Feedback d’erreurs de placement**: afficher la raison (case occupée / manque de wood / manque de gold / cap atteint).
- **Tooltips UI**: au hover/clic sur un bouton bâtiment, afficher coût + production + impact.
- **Indicateurs simples**:
  - “Food trend”: +/− net (prod − conso),
  - “Gold trend”: +/− net,
  - icône/texte “Famine” quand la food est insuffisante.
- **Écran victoire/défaite**:
  - victoire: déjà ok,
  - défaite: optionnelle (ex: pop à 0 pendant X secondes) — à décider.

### B. Moyen terme (2–6 semaines) — progression et contenu minimal “vendable”
- **Paliers de progression**:
  - déverrouillage de 1–2 bâtiments via objectifs (ex: atteindre 10 pop),
  - “tiers” d’amélioration (farm II, sawmill II) via coût + bonus.
- **Sinks d’or**:
  - entretien léger / taxes / services,
  - bâtiments utilitaires (marché, puits…) qui améliorent un paramètre.
- **Événements simples** (sans nouveaux systèmes lourds):
  - saisons: production food ±,
  - “boom” de population (croissance accélérée temporaire).

### C. Long terme (6+ semaines) — vers un produit complet
- **Map/terrain** (même léger) pour créer des contraintes naturelles.
- **Zonage** / variété de bâtiments (résidentiel/industriel/services).
- **Satisfaction** ou “qualité de vie” (simple) influençant la croissance.
- **Meta-progression** (scénarios, challenges, sandbox).

## Recommandations “commercialisable” (checklist)

### Design
- **3–5 boucles secondaires** autour de la boucle principale (progression, événements, améliorations, défis).
- **Choix irréversibles rares**, erreurs récupérables fréquentes.
- **Paliers** toutes les 30–60 secondes: le joueur doit sentir un progrès régulier.

### UX / UI
- HUD lisible sans overlay debug.
- Explications “just in time” (tooltips, raisons d’échec).
- Tutorial court (60–90s) guidant farm → sawmill → house → expansion.

### Contenu
- Atteindre un “pack” minimal: ~10–15 bâtiments + 3–5 upgrades.
- Scénarios (objectif temps / objectif pop / objectif ressources).

### Tech / production
- Sauvegarde/chargement.
- Options (audio, vitesse jeu si ajoutée, accessibilité).
- Profiling minimal + stabilité (pas de stutters, pas d’erreurs console).

## Ce que je ferais “tout de suite” (concret)
1) Ajouter un message HUD “manque X wood/gold” quand achat impossible.  
2) Ajouter un indicateur net “Food net: +/−” (en plus des rates).  
3) Ajouter 2–3 “upgrades” (ex: Farm II, House II) pilotés par `GameBalance`.  
4) Ajouter un mini tutoriel (texte + flèches) pour les 60 premières secondes.  

