# 🚀 Nuxt 4 + Tailwind v4 + GSAP → Cloudflare Workers (v3)

Stack : **pnpm · Oxlint + ESLint · Oxfmt · Lefthook · GitHub Actions**

---

## Étape 0 — Prérequis

| Outil | Version | Vérification |
|---|---|---|
| Node.js | ≥ 22.19 (24 LTS conseillé) | `node -v` |
| pnpm | ≥ 11 | `pnpm -v` |
| Git | récent | `git --version` |
| Compte Cloudflare | gratuit | https://dash.cloudflare.com |
| VS Code | conseillé | `code -v` |

> 🪟 Sous Windows : lance le script dans **WSL** ou **Git Bash**.

```bash
nvm install 24 && nvm use 24
npm install -g pnpm@latest

git config --global user.name "Ton Nom"
git config --global user.email "toi@exemple.fr"
```

---

## Étape 1 — Générer le projet

```bash
chmod +x init-nuxt-cf.sh
./init-nuxt-cf.sh mon-projet
cd mon-projet
```

Le nom doit être en **minuscules, chiffres et tirets** (il sert aussi de nom au Worker).

Ce que le script fait :
1. Il vérifie Node, pnpm et Git.
2. Il lance `git init` (branche `main`) et crée `.gitignore` et `.gitattributes`.
3. Il écrit `package.json` et `pnpm-workspace.yaml` (`allowBuilds`).
4. Il écrit les configs Nuxt, Wrangler, Oxlint, ESLint, Oxfmt, Lefthook et VS Code.
5. Il crée la page de démo (GSAP chargé à la demande) et une route API.
6. Il installe les dépendances, lance `nuxt prepare`, installe les hooks Git et formate le code.
7. Il fait le commit initial.

---

## Étape 2 — Ouvrir dans VS Code

```bash
code .
```

- Accepte **« Installer les extensions recommandées »**.
- **Désactive Prettier** pour ce workspace s'il est installé globalement (il est listé en « non recommandé »).
- Si tu as un avertissement TypeScript : `Ctrl/Cmd+Shift+P` → *TypeScript: Select TypeScript Version* → *Use Workspace Version*.

| Fichier | Rôle |
|---|---|
| `settings.json` | Oxfmt comme formateur, corrections Oxlint et ESLint à la sauvegarde, Tailwind IntelliSense, LF |
| `extensions.json` | Vue, Oxc, ESLint, Tailwind, Nuxtr, ErrorLens, EditorConfig |
| `tasks.json` | `Ctrl/Cmd+Shift+B` lance `pnpm dev`. Tâches build, preview, ship, lint, format, typecheck, check |
| `launch.json` | Debug client (Chrome), serveur (pnpm), ou les deux (« fullstack ») |

---

## Étape 3 — Développer en local

```bash
pnpm dev             # http://localhost:3000
```

### Qualité du code

```bash
pnpm lint            # Oxlint (rapide) puis ESLint (Vue/Nuxt seulement)
pnpm lint:fix        # corrections auto
pnpm format          # Oxfmt (+ tri des classes Tailwind)
pnpm format:check    # vérifie sans modifier (utilisé en CI)
pnpm typecheck       # vue-tsc
pnpm check           # les trois d'un coup
```

| Outil | Rôle |
|---|---|
| **Oxlint** | La majorité des règles JS/TS, en Rust, très rapide |
| **ESLint** | Uniquement ce qu'Oxlint ne couvre pas (templates Vue, règles Nuxt). Les doublons sont coupés par `eslint-plugin-oxlint` |
| **Oxfmt** | Formatage de tous les fichiers (TS, Vue, CSS, JSON, MD, YAML) et tri des classes Tailwind |

### Ajouter des paquets

```bash
pnpm add <paquet>
pnpm add -D <paquet>
pnpm remove <paquet>
pnpm update --interactive --latest
```

---

## Étape 4 — Animer avec GSAP

GSAP **n'est plus chargé globalement**. Le composable `useGsap` l'importe uniquement sur les pages qui l'utilisent, désactive les animations si l'utilisateur préfère moins d'animations (`prefers-reduced-motion`) et nettoie tout au démontage.

```vue
<script setup lang="ts">
const el = ref<HTMLElement | null>(null)

useGsap(({ gsap, ScrollTrigger }) => {
  gsap.to('.box', {
    x: 200,
    rotation: 360,
    scrollTrigger: { trigger: '.box', start: 'top 80%' },
  })
}, el)
</script>

<template>
  <div ref="el"><div class="box size-16 rounded bg-brand-500" /></div>
</template>
```

### Ajouter un plugin (ex. SplitText, gratuit)

Dans `app/composables/useGsap.ts`, ajoute l'import dans le `Promise.all`, puis enregistre le plugin :

```ts
const [{ gsap }, { ScrollTrigger }, { SplitText }] = await Promise.all([
  import('gsap'),
  import('gsap/ScrollTrigger'),
  import('gsap/SplitText'),
])
gsap.registerPlugin(ScrollTrigger, SplitText)
```

Ajoute ensuite `SplitText` au type `GsapTools` et à l'objet passé à `setup`.

> 💡 Le hero est masqué en CSS (`main.css`) jusqu'à ce que GSAP l'anime, pour éviter un flash. Si tu ajoutes d'autres éléments masqués de cette façon, anime-les avec `fromTo(..., { autoAlpha: 1 })`, pas avec `from`.

---

## Étape 5 — Tailwind v4 et polices

Tout se passe dans le CSS, il n'y a pas de `tailwind.config.js` :

```css
/* app/assets/css/main.css */
@import "tailwindcss";
@theme {
  --color-brand-500: #6366f1;   /* → bg-brand-500, text-brand-500… */
}
```

Les polices sont gérées par **`@nuxt/fonts`** dans `nuxt.config.ts`. Elles sont téléchargées au build et servies depuis ton domaine (pas de requête vers Google) :

```ts
fonts: {
  families: [{ name: 'Inter', provider: 'google', weights: [400, 600, 700] }],
},
```

---

## Étape 6 — Rendu et cache (`routeRules`)

```ts
routeRules: {
  '/': { prerender: true },                // HTML généré au build
  '/api/**': { cache: { maxAge: 60 } },    // cache Nitro 60 s
},
```

- **`prerender`** : la page est servie comme un fichier statique, sans exécuter le Worker. Ajoute ici tes pages qui ne changent pas (`/about`, `/blog/**`…).
- Attention : sur une page prérendue, les données chargées côté serveur sont figées au moment du build. Pour avoir des données à jour, utilise `useFetch(..., { server: false })` (c'est ce que fait la démo) ou ne prérends pas la page.

---

## Étape 7 — Git et hooks (Lefthook)

| Fichier | Rôle |
|---|---|
| `.gitignore` | Ignore `node_modules`, `.nuxt`, `.output`, `.wrangler`, `.env*`, `.dev.vars*`. Garde les fichiers partagés de `.vscode` |
| `.gitattributes` | LF partout (CRLF pour `.bat`/`.ps1`), binaires marqués, diff de `pnpm-lock.yaml` masqué |
| `lefthook.yml` | **pre-commit** : Oxlint et Oxfmt en parallèle sur les fichiers indexés. **pre-push** : typecheck |

```bash
git add -A && git commit -m "feat: ma fonctionnalité"   # les hooks se lancent tout seuls

LEFTHOOK=0 git commit -m "wip"     # sauter les hooks exceptionnellement
pnpm lefthook install              # réinstaller les hooks (après un clone)

git remote add origin git@github.com:<toi>/mon-projet.git
git push -u origin main
```

> Après un `git clone`, `pnpm install` réinstalle normalement les hooks tout seul (Lefthook est dans `allowBuilds`). Si ce n'est pas le cas, lance `pnpm lefthook install`.

---

## Étape 8 — Se connecter à Cloudflare (une seule fois)

```bash
pnpm wrangler login
pnpm wrangler whoami
```

---

## Étape 9 — Tester avec le vrai runtime Workers

```bash
cp .dev.vars.example .dev.vars   # optionnel
pnpm preview                     # build + wrangler dev → http://localhost:8787
```

> `pnpm dev` tourne sur Node. `pnpm preview` tourne sur **workerd**, le runtime de Cloudflare. Teste toujours avec `preview` avant de mettre en ligne.

---

## Étape 10 — Mettre en ligne 🚀

```bash
pnpm ship            # production
pnpm ship:preview    # version d'aperçu (URL dédiée, la prod n'est pas touchée)
pnpm wrangler tail   # logs en direct
```

> ⚠️ Le script s'appelle `ship` et pas `deploy`, parce que `pnpm deploy` est une commande native de pnpm (pour les monorepos).

L'URL de prod : `https://mon-projet.<ton-sous-domaine>.workers.dev`

### Secrets

```bash
pnpm wrangler secret put NUXT_API_SECRET
pnpm wrangler secret list
pnpm wrangler secret delete NUXT_API_SECRET
```

- En local, les variables vont dans `.dev.vars` (ignoré par Git).
- Les variables `NUXT_*` remplacent les clés de `runtimeConfig`.

### Bindings KV / D1 / R2 (optionnel)

```bash
pnpm wrangler kv namespace create CACHE
pnpm wrangler d1 create my-db
pnpm wrangler r2 bucket create my-bucket
pnpm cf-typegen      # génère worker-configuration.d.ts
```

Copie les ID dans `wrangler.jsonc`, puis accède aux bindings dans une route serveur via `event.context.cloudflare.env.CACHE`. Pour avoir les bindings aussi pendant `pnpm dev` : `pnpm nuxt module add nitro-cloudflare-dev`.

---

## Étape 11 — CI GitHub Actions

Le workflow `.github/workflows/ci.yml` fonctionne ainsi :

| Événement | Ce qui se passe |
|---|---|
| Pull request | `pnpm check`, puis **version d'aperçu** (`wrangler versions upload`) |
| Push sur `main` | `pnpm check`, puis **déploiement en production** |

1. Crée un token Cloudflare : *My Profile → API Tokens → Create Token → « Edit Cloudflare Workers »*.
2. Ajoute deux secrets dans GitHub (*Settings → Secrets and variables → Actions*) : `CLOUDFLARE_API_TOKEN` et `CLOUDFLARE_ACCOUNT_ID`.
3. Fais un **premier `pnpm ship` à la main** : une version d'aperçu ne peut être envoyée qu'à un Worker qui existe déjà.
4. Commite toujours `pnpm-lock.yaml`, sans quoi `--frozen-lockfile` échoue.

---

## Étape 12 — (Optionnel) Images avec `@nuxt/image`

```bash
pnpm nuxt module add image
```

Sur Workers, le moteur d'optimisation par défaut (sharp/IPX) ne tourne pas. Deux options :

**A. Tu as un domaine sur Cloudflare** : active *Images → Transformations* sur ta zone, puis :

```ts
image: {
  provider: 'cloudflare',
  cloudflare: { baseURL: 'https://monsite.fr' },
},
```

**B. Pas de domaine (seulement `*.workers.dev`)** : optimise tes images avant de les mettre dans `public/` (en AVIF ou WebP) et utilise de simples balises `<img>` avec `loading="lazy"` et des dimensions explicites.

---

## Étape 13 — (Optionnel) Domaine personnalisé

Dashboard → *Workers & Pages* → ton Worker → *Settings → Domains & Routes* → *Add Custom Domain*. Tu peux aussi le faire dans `wrangler.jsonc` :

```jsonc
"routes": [{ "pattern": "monsite.fr", "custom_domain": true }]
```

---

## Étape 14 — (Optionnel) Préparer Nuxt 5

Sur une branche dédiée, décommente dans `nuxt.config.ts` :

```ts
future: { compatibilityVersion: 5 },
```

Lance ensuite `pnpm check && pnpm preview` et corrige ce qui casse.

---

## 🧰 Récap des commandes

| Commande | Action |
|---|---|
| `pnpm install` | Dépendances + `nuxt prepare` + hooks |
| `pnpm dev` | Dev local (Node), :3000 |
| `pnpm build` | Build de production |
| `pnpm preview` | Build + runtime Workers en local, :8787 |
| `pnpm ship` | Mise en ligne en production |
| `pnpm ship:preview` | Version d'aperçu |
| `pnpm check` | Lint, format et types |
| `pnpm lint` / `lint:fix` | Oxlint puis ESLint |
| `pnpm format` / `format:check` | Oxfmt |
| `pnpm typecheck` | vue-tsc |
| `pnpm cf-typegen` | Types des bindings |
| `pnpm approve-builds` | Autorise les scripts d'install d'un nouveau paquet |
| `pnpm wrangler tail` | Logs de production |

---

## 🩹 Dépannage

| Problème | Solution |
|---|---|
| VS Code formate encore avec Prettier | Désactive l'extension Prettier pour ce workspace et vérifie `editor.defaultFormatter: "oxc.oxc-vscode"` |
| L'extension Oxc ne formate rien | Oxfmt doit être installé dans le projet : `pnpm install`, puis recharge la fenêtre |
| Les classes Tailwind ne sont pas triées | Vérifie `sortTailwindcss.stylesheet` dans `.oxfmtrc.json` |
| ESLint signale les mêmes erreurs qu'Oxlint | `eslint-plugin-oxlint` doit être passé en dernier à `withNuxt(...)` |
| Les hooks ne se lancent pas | `pnpm lefthook install` |
| « Ignored build scripts » | `pnpm approve-builds` ou ajoute le paquet dans `allowBuilds` |
| Un paquet tout juste publié n'est pas installé | Protection `minimumReleaseAge` de pnpm 11 : attends un peu ou règle-la dans `pnpm-workspace.yaml` |
| `ERR_PNPM_OUTDATED_LOCKFILE` en CI | `pnpm install` en local, puis commite `pnpm-lock.yaml` |
| La version d'aperçu échoue en CI | Fais d'abord un `pnpm ship` à la main pour créer le Worker |
| Le hero reste invisible | Anime-le avec `fromTo` vers `autoAlpha: 1` (le CSS le masque au départ) |
| Données figées sur une page prérendue | `useFetch(..., { server: false })` ou retire `prerender` |
| « Node.js module not supported » | Vérifie `"nodejs_compat"` dans `compatibility_flags` |
| `bad interpreter: /bin/bash^M` | `git add --renormalize .` |
