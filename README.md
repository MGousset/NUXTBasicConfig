# 🚀 Nuxt + Tailwind + GSAP sur Cloudflare Workers

Guide étape par étape pour initialiser, développer et déployer le projet.

## Stack

| Outil | Rôle |
|---|---|
| Nuxt 4 | Framework Vue full-stack (SSR) |
| Tailwind CSS v4 | Styles utilitaires (via `@tailwindcss/vite`) |
| GSAP + ScrollTrigger | Animations |
| Wrangler | CLI Cloudflare (dev local et déploiement) |
| ESLint + Prettier | Qualité et formatage du code |

---

## 0. Prérequis

- Node.js **>= 20** (`node -v`)
- npm
- Git
- Un compte Cloudflare (gratuit) : https://dash.cloudflare.com/sign-up
- VS Code (conseillé)

```bash
node -v && npm -v && git --version
npm i -g pnpm && pnpm -v
```

---

## 1. Initialisation automatique

```bash
chmod +x init-nuxt-cf.sh
./init-nuxt-cf.sh mon-projet
cd mon-projet
```

> L'assistant Nuxt peut te poser quelques questions (modules officiels, etc.).
> Tu peux tout refuser : le script installe déjà ce qu'il faut.

---

## 2. Installation manuelle (si tu ne veux pas passer par le script)

### 2.1 Créer le projet
```bash
npm create nuxt@latest mon-projet -- --template minimal
cd mon-projet
```

### 2.2 Tailwind CSS v4
```bash
npm install -D tailwindcss @tailwindcss/vite
```
- Ajoute `tailwindcss()` dans `vite.plugins` de `nuxt.config.ts`
- Crée `app/assets/css/main.css` avec `@import "tailwindcss";`
- Ajoute `css: ['~/assets/css/main.css']` dans `nuxt.config.ts`

### 2.3 GSAP
```bash
npm install gsap
```
- Crée `app/plugins/gsap.client.ts` (enregistre ScrollTrigger)
- Crée `app/composables/useGsap.ts` (contexte et nettoyage automatique)

### 2.4 Cloudflare / Wrangler
```bash
npm install -D wrangler
```
- Dans `nuxt.config.ts` : `nitro.preset = 'cloudflare_module'`
- Crée `wrangler.jsonc` (voir le script)

### 2.5 Lint & formatage
```bash
npm install -D @nuxt/eslint eslint prettier prettier-plugin-tailwindcss typescript vue-tsc
```

---

## 3. Développement

```bash
npm run dev
```
➡️ http://localhost:3000

Dans VS Code :
- `Ctrl/Cmd + Shift + B` → lance la tâche par défaut **Nuxt: dev**
- `F5` → **fullstack: nuxt** (debug serveur + Chrome)
- Installe les extensions recommandées quand VS Code te le propose

---

## 4. Connexion à Cloudflare (une seule fois)

```bash
npm run cf:login
# équivalent : npx wrangler login
```
Une page s'ouvre dans le navigateur pour autoriser Wrangler.

Vérifier :
```bash
npx wrangler whoami
```

---

## 5. Tester dans le runtime Cloudflare en local

```bash
npm run preview
```
➡️ http://localhost:8787

Ça build le projet puis le lance dans `workerd`, le même runtime qu'en prod.
Teste toujours ici avant de déployer.

Secrets locaux :
```bash
cp .dev.vars.example .dev.vars
```

---

## 6. Déploiement

```bash
npm run deploy
```
L'URL s'affiche à la fin : `https://<nom-du-projet>.<ton-sous-domaine>.workers.dev`

### Secrets en production
```bash
pnpm wrangler secret put NUXT_API_SECRET
```

### Logs en temps réel
```bash
pnpm wrangler tail
```

---

## 7. Déploiement automatique (GitHub Actions)

1. Pousse le repo sur GitHub :
   ```bash
   git remote add origin git@github.com:<toi>/mon-projet.git
   git push -u origin main
   ```
2. Sur Cloudflare : **My Profile → API Tokens → Create Token** → modèle *Edit Cloudflare Workers*
3. Sur GitHub : **Settings → Secrets and variables → Actions**, ajoute :
   - `CLOUDFLARE_API_TOKEN`
   - `CLOUDFLARE_ACCOUNT_ID` (visible dans le dashboard Cloudflare)
4. Chaque push sur `main` déclenche un déploiement automatique ✅

---

## 8. Commandes utiles

| Commande | Description |
|---|---|
| `pnpm run dev` | Serveur de dev Nuxt |
| `pnpm run build` | Build de production |
| `pnpm run preview` | Build + test local avec Wrangler |
| `pnpm run deploy` | Build + déploiement Cloudflare |
| `pnpm run cf:typegen` | Génère les types des bindings Cloudflare |
| `pnpm run lint` / `lint:fix` | Analyse / corrige le code |
| `pnpm run format` | Formate avec Prettier |
| `pnpm run typecheck` | Vérifie les types TypeScript |
| `pnpm wrangler tail` | Logs de production en direct |

---

## 9. Structure du projet

```
mon-projet/
├── .github/workflows/deploy.yml
├── .vscode/
│   ├── extensions.json
│   ├── launch.json
│   ├── settings.json
│   └── tasks.json
├── app/
│   ├── assets/css/main.css
│   ├── composables/useGsap.ts
│   ├── plugins/gsap.client.ts
│   └── app.vue
├── public/
├── server/
├── nuxt.config.ts
├── wrangler.jsonc
├── eslint.config.mjs
├── .prettierrc
├── .editorconfig
└── package.json
```

---

## 10. Dépannage

| Problème | Solution |
|---|---|
| `eslint.config.mjs` introuvable | Lance `npx nuxt prepare` |
| Erreur de module Node au déploiement | Vérifie `nodejs_compat` dans `wrangler.jsonc` |
| Les classes Tailwind ne s'appliquent pas | Vérifie l'import de `main.css` dans `nuxt.config.ts` |
| GSAP plante en SSR | N'utilise GSAP que dans `onMounted` (ou via `useGsap`) |
| Le nom du Worker est refusé | Uniquement des minuscules, chiffres et tirets |
