#!/usr/bin/env bash
# =============================================================================
#  init-nuxt-cf.sh — v3
#  Nuxt 4 + Tailwind v4 + GSAP + Cloudflare Workers
#  pnpm · Oxlint + ESLint (Vue) · Oxfmt · Lefthook · GitHub Actions
#  Usage : ./init-nuxt-cf.sh <nom-du-projet>
# =============================================================================
set -euo pipefail

APP_NAME="${1:-my-nuxt-app}"
COMPAT_DATE="$(date +%Y-%m-%d)"

info() { printf "\033[1;34m▶ %s\033[0m\n" "$*"; }
ok()   { printf "\033[1;32m✔ %s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m⚠ %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✖ %s\033[0m\n" "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 0. Vérifications
# ----------------------------------------------------------------------------
info "Vérification des prérequis"
command -v node >/dev/null || fail "Node.js introuvable (>= 22.19 requis, 24 LTS conseillé)"
command -v pnpm >/dev/null || fail "pnpm introuvable → npm install -g pnpm@latest"
command -v git  >/dev/null || fail "git introuvable"

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
NODE_MINOR="$(node -p 'process.versions.node.split(".")[1]')"
if [ "$NODE_MAJOR" -lt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -lt 19 ]; }; then
  fail "Node $(node -v) détecté, il faut >= 22.19 (24 LTS conseillé)"
fi

PNPM_VERSION="$(pnpm -v)"
PNPM_MAJOR="${PNPM_VERSION%%.*}"
[ "$PNPM_MAJOR" -ge 11 ] || fail "pnpm $PNPM_VERSION détecté, il faut >= 11 → npm install -g pnpm@latest"

if ! [[ "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; then
  fail "Nom invalide : minuscules, chiffres et tirets uniquement (contrainte Cloudflare)"
fi
[ -e "$APP_NAME" ] && fail "Le dossier '$APP_NAME' existe déjà"

GIT_USER_OK=true
if [ -z "$(git config user.name || true)" ] || [ -z "$(git config user.email || true)" ]; then
  GIT_USER_OK=false
  warn "git user.name / user.email non configurés : le commit initial sera ignoré"
fi
ok "Node $(node -v) / pnpm $PNPM_VERSION / $(git --version)"

# ----------------------------------------------------------------------------
# 1. Arborescence + Git (avant l'install, pour que Lefthook pose ses hooks)
# ----------------------------------------------------------------------------
info "Création de l'arborescence"
mkdir -p "$APP_NAME"/{app/{assets/css,components,composables,pages},server/api,public,.vscode,.github/workflows}
cd "$APP_NAME"

info "Initialisation Git"
git -c init.defaultBranch=main init -q

cat > .gitignore <<'EOF'
# --- Dépendances ---
node_modules
.pnpm-store

# --- Nuxt / Nitro ---
.nuxt
.output
.nitro
.cache
.data
dist

# --- Cloudflare / Wrangler ---
.wrangler
.dev.vars*
!.dev.vars.example

# --- Environnement ---
.env
.env.*
!.env.example

# --- Lefthook (surcharges perso) ---
lefthook-local.yml

# --- Logs ---
logs
*.log
pnpm-debug.log*

# --- OS / éditeurs ---
.DS_Store
Thumbs.db
.idea
*.swp
.vscode/*
!.vscode/settings.json
!.vscode/tasks.json
!.vscode/launch.json
!.vscode/extensions.json
EOF

cat > .gitattributes <<'EOF'
# LF partout dans le dépôt (cohérent avec .editorconfig / Oxfmt)
* text=auto eol=lf

# Scripts Windows : CRLF obligatoire
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.ps1  text eol=crlf

# Scripts shell : toujours LF (sinon "bad interpreter" sous WSL / Linux)
*.sh   text eol=lf

# Fichiers générés : diff masqué, ignorés dans les stats GitHub
pnpm-lock.yaml            -diff linguist-generated=true
worker-configuration.d.ts linguist-generated=true

# Binaires
*.png   binary
*.jpg   binary
*.jpeg  binary
*.gif   binary
*.webp  binary
*.avif  binary
*.ico   binary
*.woff  binary
*.woff2 binary
*.ttf   binary
*.otf   binary
*.mp4   binary
*.webm  binary
*.mp3   binary
*.pdf   binary
*.zip   binary

# SVG = texte (diffable)
*.svg   text
EOF

# ----------------------------------------------------------------------------
# 2. package.json + pnpm-workspace.yaml
# ----------------------------------------------------------------------------
cat > package.json <<EOF
{
  "name": "$APP_NAME",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@$PNPM_VERSION",
  "engines": { "node": ">=22.19" },
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "generate": "nuxt generate",
    "preview": "nuxt build && wrangler dev",
    "ship": "nuxt build && wrangler deploy",
    "ship:preview": "nuxt build && wrangler versions upload",
    "cf-typegen": "wrangler types",
    "lint": "oxlint && eslint .",
    "lint:fix": "oxlint --fix && eslint . --fix",
    "format": "oxfmt",
    "format:check": "oxfmt --check",
    "typecheck": "nuxt typecheck",
    "check": "pnpm lint && pnpm format:check && pnpm typecheck"
  }
}
EOF

# pnpm >= 11 : seuls les paquets listés ici peuvent lancer leurs scripts d'install
cat > pnpm-workspace.yaml <<'EOF'
allowBuilds:
  '@parcel/watcher': true
  '@tailwindcss/oxide': true
  esbuild: true
  lefthook: true
  unrs-resolver: true
  workerd: true
EOF

# ----------------------------------------------------------------------------
# 3. Config Nuxt / Tailwind / TypeScript / Cloudflare
# ----------------------------------------------------------------------------
info "Écriture des fichiers de configuration"

cat > nuxt.config.ts <<EOF
import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '$COMPAT_DATE',
  devtools: { enabled: true },

  // Tester les comportements de Nuxt 5 (à activer sur une branche dédiée)
  // future: { compatibilityVersion: 5 },

  modules: ['@nuxt/eslint', '@nuxt/fonts'],

  css: ['~/assets/css/main.css'],

  vite: {
    plugins: [tailwindcss()],
  },

  // Polices téléchargées au build et servies depuis ton domaine
  fonts: {
    families: [{ name: 'Inter', provider: 'google', weights: [400, 600, 700] }],
  },

  routeRules: {
    // HTML statique généré au build, servi directement par les assets Cloudflare
    '/': { prerender: true },
    // Cache Nitro (mémoire de l'instance Worker) pendant 60 s
    '/api/**': { cache: { maxAge: 60 } },
  },

  // Build pour Cloudflare Workers (Workers + Static Assets)
  nitro: {
    preset: 'cloudflare_module',
  },

  app: {
    head: {
      htmlAttrs: { lang: 'fr' },
      title: '$APP_NAME',
    },
  },
})
EOF

cat > wrangler.jsonc <<EOF
{
  "\$schema": "node_modules/wrangler/config-schema.json",
  "name": "$APP_NAME",
  "main": "./.output/server/index.mjs",
  "compatibility_date": "$COMPAT_DATE",
  "compatibility_flags": ["nodejs_compat"],
  "assets": {
    "binding": "ASSETS",
    "directory": "./.output/public/"
  },
  "observability": { "enabled": true },
  "preview_urls": true

  // Exemples de bindings (décommente après création) :
  // "kv_namespaces": [{ "binding": "CACHE", "id": "<KV_ID>" }],
  // "d1_databases": [{ "binding": "DB", "database_name": "my-db", "database_id": "<D1_ID>" }]
}
EOF

cat > tsconfig.json <<'EOF'
{
  "files": [],
  "references": [
    { "path": "./.nuxt/tsconfig.app.json" },
    { "path": "./.nuxt/tsconfig.server.json" },
    { "path": "./.nuxt/tsconfig.shared.json" },
    { "path": "./.nuxt/tsconfig.node.json" }
  ]
}
EOF

# ----------------------------------------------------------------------------
# 4. Qualité : Oxlint + ESLint (Vue/Nuxt) + Oxfmt + Lefthook
# ----------------------------------------------------------------------------
info "Configuration Oxlint / ESLint / Oxfmt / Lefthook"

cat > .oxlintrc.json <<'EOF'
{
  "$schema": "./node_modules/oxlint/configuration_schema.json",
  "plugins": ["typescript", "unicorn", "import", "vue"],
  "categories": {
    "correctness": "error",
    "suspicious": "warn"
  },
  "ignorePatterns": [".nuxt", ".output", ".wrangler", "worker-configuration.d.ts"]
}
EOF

cat > eslint.config.mjs <<'EOF'
// @ts-check
// ESLint ne garde que ce qu'Oxlint ne sait pas faire (templates Vue, règles Nuxt).
// eslint-plugin-oxlint désactive les règles en doublon : il doit rester en dernier.
import oxlint from 'eslint-plugin-oxlint'
import { withNuxt } from './.nuxt/eslint.config.mjs'

export default withNuxt(...oxlint.buildFromOxlintConfigFile('./.oxlintrc.json'))
EOF

cat > .oxfmtrc.json <<'EOF'
{
  "$schema": "./node_modules/oxfmt/configuration_schema.json",
  "printWidth": 100,
  "semi": false,
  "singleQuote": true,
  "trailingComma": "all",
  "endOfLine": "lf",
  "sortTailwindcss": {
    "stylesheet": "./app/assets/css/main.css"
  },
  "ignorePatterns": [
    ".nuxt",
    ".output",
    ".wrangler",
    "node_modules",
    "pnpm-lock.yaml",
    "worker-configuration.d.ts"
  ]
}
EOF

cat > lefthook.yml <<'EOF'
# Hooks Git rapides (binaire natif, commandes en parallèle)
pre-commit:
  parallel: true
  commands:
    lint:
      glob: "*.{js,mjs,ts,vue}"
      run: pnpm oxlint {staged_files}
    format:
      glob: "*.{js,mjs,ts,vue,json,jsonc,css,md,yml,yaml}"
      run: pnpm oxfmt --no-error-on-unmatched-pattern {staged_files}
      stage_fixed: true

pre-push:
  commands:
    typecheck:
      run: pnpm typecheck
EOF

cat > .editorconfig <<'EOF'
root = true

[*]
charset = utf-8
indent_style = space
indent_size = 2
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false
EOF

echo "24" > .nvmrc

cat > .dev.vars.example <<'EOF'
# Copie ce fichier en .dev.vars pour `wrangler dev` (jamais commité)
# En prod : pnpm wrangler secret put NOM_DU_SECRET
NUXT_API_SECRET=change-me
EOF

# ----------------------------------------------------------------------------
# 5. VS Code : settings / extensions / tasks / launch
# ----------------------------------------------------------------------------
info "Configuration VS Code"

cat > .vscode/extensions.json <<'EOF'
{
  "recommendations": [
    "Vue.volar",
    "oxc.oxc-vscode",
    "dbaeumer.vscode-eslint",
    "bradlc.vscode-tailwindcss",
    "nuxtr.nuxtr-vscode",
    "usernamehw.errorlens",
    "editorconfig.editorconfig"
  ],
  "unwantedRecommendations": ["esbenp.prettier-vscode"]
}
EOF

cat > .vscode/settings.json <<'EOF'
{
  "npm.packageManager": "pnpm",

  // Formatage : Oxfmt via l'extension Oxc
  "oxc.fmt.configPath": ".oxfmtrc.json",
  "editor.defaultFormatter": "oxc.oxc-vscode",
  "editor.formatOnSave": true,
  "editor.formatOnSaveMode": "file",
  "[vue]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[typescript]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[javascript]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[json]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[jsonc]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[tailwindcss]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[css]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[markdown]": { "editor.defaultFormatter": "oxc.oxc-vscode" },
  "[yaml]": { "editor.defaultFormatter": "oxc.oxc-vscode" },

  // Lint : corrections Oxlint puis ESLint à la sauvegarde
  "editor.codeActionsOnSave": {
    "source.fixAll.oxc": "explicit",
    "source.fixAll.eslint": "explicit"
  },

  "files.eol": "\n",
  "files.associations": {
    "*.css": "tailwindcss",
    "wrangler.json": "jsonc"
  },
  "tailwindCSS.experimental.configFile": "app/assets/css/main.css",
  "editor.quickSuggestions": { "strings": "on" },

  "typescript.tsdk": "node_modules/typescript/lib",

  "search.exclude": {
    "**/.nuxt": true,
    "**/.output": true,
    "**/.wrangler": true,
    "**/node_modules": true,
    "pnpm-lock.yaml": true
  }
}
EOF

cat > .vscode/tasks.json <<'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "nuxt: dev",
      "type": "npm",
      "script": "dev",
      "isBackground": true,
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": {
        "owner": "nuxt",
        "pattern": { "regexp": "^__never__$" },
        "background": {
          "activatesBeforeEnd": true,
          "beginsPattern": "Nuxt",
          "endsPattern": "Local:"
        }
      }
    },
    { "label": "nuxt: build", "type": "npm", "script": "build", "group": "build", "problemMatcher": [] },
    {
      "label": "cf: preview (wrangler dev)",
      "type": "npm",
      "script": "preview",
      "isBackground": true,
      "problemMatcher": {
        "owner": "wrangler",
        "pattern": { "regexp": "^__never__$" },
        "background": {
          "activatesBeforeEnd": true,
          "beginsPattern": "Building|nuxt build",
          "endsPattern": "Ready on"
        }
      }
    },
    { "label": "cf: ship (prod)", "type": "npm", "script": "ship", "problemMatcher": [] },
    { "label": "cf: ship preview (version)", "type": "npm", "script": "ship:preview", "problemMatcher": [] },
    { "label": "cf: types", "type": "npm", "script": "cf-typegen", "problemMatcher": [] },
    { "label": "lint", "type": "npm", "script": "lint", "problemMatcher": ["$eslint-stylish"] },
    { "label": "format", "type": "npm", "script": "format", "problemMatcher": [] },
    { "label": "typecheck", "type": "npm", "script": "typecheck", "problemMatcher": ["$tsc"] },
    { "label": "check (lint + format + types)", "type": "npm", "script": "check", "problemMatcher": [] },
    { "label": "pnpm: install", "type": "shell", "command": "pnpm install", "problemMatcher": [] }
  ]
}
EOF

cat > .vscode/launch.json <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "chrome",
      "request": "launch",
      "name": "client: chrome",
      "url": "http://localhost:3000",
      "webRoot": "${workspaceFolder}"
    },
    {
      "type": "node",
      "request": "launch",
      "name": "server: nuxt",
      "outputCapture": "std",
      "runtimeExecutable": "pnpm",
      "runtimeArgs": ["nuxt", "dev"],
      "cwd": "${workspaceFolder}"
    },
    {
      "type": "chrome",
      "request": "launch",
      "name": "client: chrome (wrangler :8787)",
      "url": "http://localhost:8787",
      "webRoot": "${workspaceFolder}"
    }
  ],
  "compounds": [
    {
      "name": "fullstack: nuxt",
      "configurations": ["server: nuxt", "client: chrome"]
    }
  ]
}
EOF

# ----------------------------------------------------------------------------
# 6. Code applicatif (Tailwind + GSAP à la demande + API démo)
# ----------------------------------------------------------------------------
info "Création des fichiers de l'app"

cat > app/assets/css/main.css <<'EOF'
@import "tailwindcss";

@theme {
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --color-brand-500: #6366f1;
  --color-brand-600: #4f46e5;
}

/* Évite le flash du hero avant le chargement de GSAP.
   Si l'utilisateur préfère moins d'animations, rien n'est caché. */
@media (prefers-reduced-motion: no-preference) {
  [data-anim="hero"] > * {
    visibility: hidden;
  }
}
EOF

cat > app/app.vue <<'EOF'
<template>
  <div>
    <NuxtRouteAnnouncer />
    <NuxtPage />
  </div>
</template>
EOF

cat > app/composables/useGsap.ts <<'EOF'
import type { Ref } from 'vue'

type Gsap = (typeof import('gsap'))['gsap']
type ScrollTriggerStatic = (typeof import('gsap/ScrollTrigger'))['ScrollTrigger']

export interface GsapTools {
  gsap: Gsap
  ScrollTrigger: ScrollTriggerStatic
}

/**
 * Charge GSAP + ScrollTrigger côté client, uniquement sur les pages qui l'utilisent.
 * - Animations désactivées si l'utilisateur préfère moins d'animations.
 * - Nettoyage automatique (tweens, ScrollTriggers) au démontage.
 */
export function useGsap(setup: (tools: GsapTools) => void, scope?: Ref<HTMLElement | null>) {
  let mm: ReturnType<Gsap['matchMedia']> | undefined
  let disposed = false

  onMounted(async () => {
    const [{ gsap }, { ScrollTrigger }] = await Promise.all([
      import('gsap'),
      import('gsap/ScrollTrigger'),
    ])
    if (disposed) return

    gsap.registerPlugin(ScrollTrigger)
    mm = gsap.matchMedia(scope?.value ?? undefined)
    mm.add('(prefers-reduced-motion: no-preference)', () => setup({ gsap, ScrollTrigger }))
  })

  onBeforeUnmount(() => {
    disposed = true
    mm?.revert()
  })
}
EOF

cat > app/pages/index.vue <<'EOF'
<script setup lang="ts">
const root = ref<HTMLElement | null>(null)

useGsap(({ gsap }) => {
  // fromTo : le CSS cache le hero au départ, on le rend visible ici
  gsap.fromTo(
    '[data-anim="hero"] > *',
    { y: 40, autoAlpha: 0 },
    { y: 0, autoAlpha: 1, duration: 0.9, ease: 'power3.out', stagger: 0.12 },
  )

  gsap.utils.toArray<HTMLElement>('[data-anim="card"]').forEach((card) => {
    gsap.from(card, {
      y: 60,
      autoAlpha: 0,
      duration: 0.8,
      ease: 'power2.out',
      scrollTrigger: { trigger: card, start: 'top 85%' },
    })
  })
}, root)

// Page prérendue : on appelle l'API côté client pour voir le Worker répondre en live
const { data } = useFetch('/api/hello', { server: false, lazy: true })
</script>

<template>
  <main ref="root" class="min-h-screen bg-zinc-950 font-sans text-zinc-100">
    <section
      data-anim="hero"
      class="mx-auto flex min-h-screen max-w-3xl flex-col items-center justify-center gap-6 px-6 text-center"
    >
      <h1 class="text-5xl font-bold tracking-tight md:text-7xl">
        Nuxt <span class="text-brand-500">×</span> Tailwind
        <span class="text-brand-500">×</span> GSAP
      </h1>
      <p class="text-lg text-zinc-400">Prérendu et servi par Cloudflare Workers.</p>
      <p class="font-mono text-sm text-zinc-500">API : {{ data?.message ?? '…' }}</p>
    </section>

    <section class="mx-auto grid max-w-5xl gap-6 px-6 pb-32 md:grid-cols-3">
      <article
        v-for="n in 6"
        :key="n"
        data-anim="card"
        class="rounded-2xl border border-zinc-800 bg-zinc-900 p-6"
      >
        <h2 class="mb-2 text-xl font-semibold">Card {{ n }}</h2>
        <p class="text-zinc-400">Animée au scroll avec ScrollTrigger.</p>
      </article>
    </section>
  </main>
</template>
EOF

cat > server/api/hello.ts <<'EOF'
export default defineEventHandler(() => ({
  message: 'Hello depuis un Cloudflare Worker 👋',
  time: new Date().toISOString(),
}))
EOF

cat > public/robots.txt <<'EOF'
User-agent: *
Allow: /
EOF

# ----------------------------------------------------------------------------
# 7. CI GitHub Actions : check → deploy (main) / version d'aperçu (PR)
# ----------------------------------------------------------------------------
cat > .github/workflows/ci.yml <<'EOF'
name: CI / Deploy

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: pnpm/action-setup@v4 # lit "packageManager" dans package.json
      - uses: actions/setup-node@v5
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm check

  deploy:
    needs: check
    # Pas de secrets sur les PR venant de forks → on saute
    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v5
        with:
          node-version-file: .nvmrc
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm build
      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          packageManager: pnpm
          # main → production ; PR → version d'aperçu, la prod n'est pas touchée
          command: ${{ github.event_name == 'pull_request' && 'versions upload' || 'deploy' }}
EOF

# ----------------------------------------------------------------------------
# 8. Installation des dépendances
# ----------------------------------------------------------------------------
info "Installation des dépendances (runtime)"
pnpm add nuxt vue vue-router gsap

info "Installation des dépendances (dev)"
pnpm add -D \
  tailwindcss @tailwindcss/vite \
  @nuxt/fonts \
  wrangler \
  oxlint oxfmt \
  @nuxt/eslint eslint eslint-plugin-oxlint \
  typescript@~6.0.3 vue-tsc \
  lefthook

# postinstall ajouté APRÈS l'install, sinon `nuxt prepare` se lance
# alors que les modules Nuxt ne sont pas encore installés
node -e '
const fs = require("fs");
const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
p.scripts.postinstall = "nuxt prepare";
fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
'
pnpm nuxt prepare

info "Installation des hooks Git (Lefthook)"
pnpm lefthook install

info "Formatage initial (Oxfmt)"
pnpm format

# ----------------------------------------------------------------------------
# 9. Commit initial
# ----------------------------------------------------------------------------
info "Commit initial"
git add -A
if $GIT_USER_OK; then
  # LEFTHOOK=0 : on saute les hooks pour ce commit (tout vient d'être formaté)
  LEFTHOOK=0 git commit -qm "chore: init Nuxt + Tailwind + GSAP + Cloudflare Workers (v3)"
  ok "Commit initial créé sur 'main'"
else
  warn "Fichiers indexés mais non commités. Configure Git puis :"
  echo '    git config --global user.name "Ton Nom"'
  echo '    git config --global user.email "toi@exemple.fr"'
  echo '    git commit -m "chore: init"'
fi

# ----------------------------------------------------------------------------
# Fin
# ----------------------------------------------------------------------------
ok "Projet '$APP_NAME' prêt !"
cat <<EOF

Prochaines étapes :
  cd $APP_NAME
  code .                  # ouvre VS Code (installe les extensions recommandées)
  pnpm dev                # http://localhost:3000
  pnpm check              # lint + format + types
  pnpm wrangler login     # connexion Cloudflare (une seule fois)
  pnpm preview            # runtime Workers en local -> http://localhost:8787
  pnpm ship               # mise en ligne sur *.workers.dev

EOF
