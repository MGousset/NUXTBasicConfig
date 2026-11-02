#!/usr/bin/env bash
# ============================================================
#  init-nuxt-cf.sh (pnpm)
#  Nuxt 4 + Tailwind v4 + GSAP + Cloudflare Workers (Wrangler)
#  Usage : ./init-nuxt-cf.sh mon-projet
# ============================================================
set -euo pipefail

# ---------- Couleurs ----------
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${BLUE}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✔ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✖ $1${NC}"; exit 1; }

# ---------- Arguments ----------
PROJECT_NAME="${1:-}"
[ -z "$PROJECT_NAME" ] && fail "Usage : ./init-nuxt-cf.sh <nom-du-projet>"
[ -d "$PROJECT_NAME" ] && fail "Le dossier '$PROJECT_NAME' existe déjà."

WORKER_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
TODAY=$(date +%F)

# ---------- Prérequis ----------
step "Vérification des prérequis"
command -v node >/dev/null || fail "Node.js n'est pas installé."
NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
[ "$NODE_MAJOR" -lt 20 ] && fail "Node >= 20 requis (actuel : $(node -v))."

if ! command -v pnpm >/dev/null; then
  warn "pnpm introuvable, installation globale via npm..."
  npm install -g pnpm || fail "Impossible d'installer pnpm (essaie avec sudo ou via https://pnpm.io/installation)."
fi
PNPM_VERSION=$(pnpm -v)
ok "Node $(node -v) / pnpm $PNPM_VERSION"

# ---------- 1. Création du projet Nuxt (sans install) ----------
step "Création du projet Nuxt"
pnpm create nuxt@latest "$PROJECT_NAME" \
  --template minimal \
  --packageManager pnpm \
  --gitInit \
  --no-install
cd "$PROJECT_NAME"

if [ -d "app" ]; then SRC="app"; else SRC="."; fi
ok "Projet créé (dossier source : $SRC)"

# ---------- 2. Config pnpm (avant toute installation) ----------
step "Configuration de pnpm"
cat > pnpm-workspace.yaml <<'EOF'
# Paquets autorisés à exécuter leurs scripts d'installation (pnpm v10+)
onlyBuiltDependencies:
  - '@parcel/watcher'
  - esbuild
  - sharp
  - unrs-resolver
  - workerd
EOF

npm pkg set packageManager="pnpm@${PNPM_VERSION}"
ok "pnpm-workspace.yaml + packageManager=pnpm@${PNPM_VERSION}"

# ---------- 3. Dépendances ----------
step "Installation des dépendances"
pnpm install
pnpm add gsap
pnpm add -D tailwindcss @tailwindcss/vite \
  wrangler \
  @nuxt/eslint eslint \
  prettier prettier-plugin-tailwindcss \
  typescript vue-tsc
ok "Dépendances installées"

# ---------- 4. nuxt.config.ts ----------
step "Configuration de Nuxt"
cat > nuxt.config.ts <<EOF
import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  compatibilityDate: '${TODAY}',
  devtools: { enabled: true },

  modules: ['@nuxt/eslint'],

  css: ['~/assets/css/main.css'],

  vite: {
    plugins: [tailwindcss()],
  },

  nitro: {
    preset: 'cloudflare_module',
    cloudflare: {
      nodeCompat: true,
    },
  },

  typescript: {
    strict: true,
  },
})
EOF
ok "nuxt.config.ts"

# ---------- 5. Tailwind ----------
step "Configuration de Tailwind CSS v4"
mkdir -p "$SRC/assets/css"
cat > "$SRC/assets/css/main.css" <<'EOF'
@import "tailwindcss";

@theme {
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --color-brand: #6366f1;
}
EOF
ok "main.css"

# ---------- 6. GSAP ----------
step "Configuration de GSAP"
mkdir -p "$SRC/plugins" "$SRC/composables"

cat > "$SRC/plugins/gsap.client.ts" <<'EOF'
import { gsap } from 'gsap'
import { ScrollTrigger } from 'gsap/ScrollTrigger'

export default defineNuxtPlugin(() => {
  gsap.registerPlugin(ScrollTrigger)

  return {
    provide: { gsap, ScrollTrigger },
  }
})
EOF

cat > "$SRC/composables/useGsap.ts" <<'EOF'
import type { Ref } from 'vue'

/**
 * Crée un contexte GSAP lié à un élément, avec nettoyage automatique
 * au démontage du composant (évite les fuites d'animations / ScrollTriggers).
 */
export function useGsap(
  scope: Ref<HTMLElement | null>,
  setup: (gsap: typeof import('gsap').gsap) => void,
) {
  const { $gsap } = useNuxtApp()
  let ctx: ReturnType<typeof $gsap.context> | undefined

  onMounted(() => {
    if (!scope.value) return
    ctx = $gsap.context(() => setup($gsap), scope.value)
  })

  onBeforeUnmount(() => ctx?.revert())
}
EOF

cat > "$SRC/app.vue" <<'EOF'
<script setup lang="ts">
const root = ref<HTMLElement | null>(null)

useGsap(root, (gsap) => {
  gsap.from('.hero-title', { y: 60, opacity: 0, duration: 1, ease: 'power3.out' })
  gsap.from('.hero-sub', { y: 30, opacity: 0, duration: 1, delay: 0.2, ease: 'power3.out' })

  gsap.utils.toArray<HTMLElement>('.box').forEach((box) => {
    gsap.from(box, {
      scrollTrigger: { trigger: box, start: 'top 85%' },
      y: 80,
      opacity: 0,
      duration: 0.8,
      ease: 'power2.out',
    })
  })
})
</script>

<template>
  <main ref="root" class="min-h-screen bg-slate-950 text-white">
    <section class="flex h-screen flex-col items-center justify-center gap-4 text-center">
      <h1 class="hero-title text-6xl font-bold text-brand">Nuxt + Tailwind + GSAP</h1>
      <p class="hero-sub text-lg text-slate-400">Déployé sur Cloudflare Workers 🚀</p>
    </section>

    <section class="mx-auto grid max-w-4xl gap-8 px-6 pb-32">
      <div
        v-for="i in 6"
        :key="i"
        class="box rounded-2xl bg-slate-800 p-10 text-2xl font-semibold"
      >
        Bloc {{ i }}
      </div>
    </section>
  </main>
</template>
EOF
ok "Plugin, composable et page de démo GSAP"

# ---------- 7. Wrangler ----------
step "Configuration de Wrangler"
cat > wrangler.jsonc <<EOF
{
  "\$schema": "node_modules/wrangler/config-schema.json",
  "name": "${WORKER_NAME}",
  "main": "./.output/server/index.mjs",
  "compatibility_date": "${TODAY}",
  "compatibility_flags": ["nodejs_compat"],
  "assets": {
    "binding": "ASSETS",
    "directory": "./.output/public/"
  },
  "observability": {
    "enabled": true
  }
}
EOF

cat > .dev.vars.example <<'EOF'
# Copie ce fichier en .dev.vars pour tes secrets locaux (wrangler dev)
# NUXT_API_SECRET=changeme
EOF
ok "wrangler.jsonc"

# ---------- 8. Scripts ----------
step "Ajout des scripts"
npm pkg set \
  scripts.preview="pnpm build && wrangler dev" \
  scripts.deploy="pnpm build && wrangler deploy" \
  scripts.cf:typegen="wrangler types" \
  scripts.cf:login="wrangler login" \
  scripts.lint="eslint ." \
  scripts.lint:fix="eslint . --fix" \
  scripts.format="prettier --write ." \
  scripts.typecheck="nuxt typecheck"
ok "Scripts ajoutés"

# ---------- 9. ESLint / Prettier / EditorConfig ----------
step "Lint & formatage"
cat > eslint.config.mjs <<'EOF'
import withNuxt from './.nuxt/eslint.config.mjs'

export default withNuxt()
EOF

cat > .prettierrc <<'EOF'
{
  "semi": false,
  "singleQuote": true,
  "printWidth": 100,
  "trailingComma": "all",
  "plugins": ["prettier-plugin-tailwindcss"]
}
EOF

cat > .prettierignore <<'EOF'
.nuxt
.output
.wrangler
node_modules
dist
pnpm-lock.yaml
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
EOF

cat >> .gitignore <<'EOF'

# Cloudflare
.wrangler
.dev.vars*
!.dev.vars.example
worker-configuration.d.ts

# Lockfiles d'autres gestionnaires (on utilise pnpm)
package-lock.json
yarn.lock
EOF
ok "ESLint, Prettier, EditorConfig, .gitignore"

# ---------- 10. VS Code ----------
step "Configuration VS Code"
mkdir -p .vscode

cat > .vscode/extensions.json <<'EOF'
{
  "recommendations": [
    "Vue.volar",
    "bradlc.vscode-tailwindcss",
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "EditorConfig.EditorConfig",
    "antfu.goto-alias"
  ]
}
EOF

cat > .vscode/settings.json <<EOF
{
  "npm.packageManager": "pnpm",

  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit"
  },
  "eslint.useFlatConfig": true,
  "eslint.validate": ["javascript", "typescript", "vue"],

  "files.associations": {
    "*.css": "tailwindcss",
    "wrangler.json": "jsonc"
  },
  "tailwindCSS.experimental.configFile": "${SRC}/assets/css/main.css",
  "tailwindCSS.classAttributes": ["class", "ui", ":class"],
  "editor.quickSuggestions": { "strings": "on" },

  "typescript.tsdk": "node_modules/typescript/lib",

  "files.exclude": {
    "**/.nuxt": true,
    "**/.output": true,
    "**/.wrangler": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/.nuxt": true,
    "**/.output": true,
    "pnpm-lock.yaml": true
  }
}
EOF

cat > .vscode/tasks.json <<'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Nuxt: dev",
      "type": "shell",
      "command": "pnpm dev",
      "isBackground": true,
      "problemMatcher": [],
      "group": { "kind": "build", "isDefault": true }
    },
    { "label": "Nuxt: build", "type": "shell", "command": "pnpm build", "problemMatcher": [] },
    {
      "label": "Cloudflare: preview (wrangler dev)",
      "type": "shell",
      "command": "pnpm preview",
      "isBackground": true,
      "problemMatcher": []
    },
    { "label": "Cloudflare: deploy", "type": "shell", "command": "pnpm deploy:cf", "problemMatcher": [] },
    { "label": "Cloudflare: login", "type": "shell", "command": "pnpm cf:login", "problemMatcher": [] },
    { "label": "Cloudflare: typegen", "type": "shell", "command": "pnpm cf:typegen", "problemMatcher": [] },
    { "label": "Lint: fix", "type": "shell", "command": "pnpm lint:fix", "problemMatcher": ["$eslint-stylish"] },
    { "label": "Typecheck", "type": "shell", "command": "pnpm typecheck", "problemMatcher": ["$tsc"] },
    { "label": "pnpm: install", "type": "shell", "command": "pnpm install", "problemMatcher": [] }
  ]
}
EOF

cat > .vscode/launch.json <<'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "server: nuxt",
      "outputCapture": "std",
      "program": "${workspaceFolder}/node_modules/nuxt/bin/nuxt.mjs",
      "args": ["dev"]
    },
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
      "name": "cloudflare: wrangler dev",
      "runtimeExecutable": "pnpm",
      "runtimeArgs": ["preview"],
      "console": "integratedTerminal"
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
ok ".vscode/ (settings, tasks, launch, extensions)"

# ---------- 11. GitHub Actions ----------
step "Workflow GitHub Actions"
mkdir -p .github/workflows
cat > .github/workflows/deploy.yml <<'EOF'
name: Deploy to Cloudflare Workers

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Lit la version dans le champ "packageManager" du package.json
      - uses: pnpm/action-setup@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm

      - run: pnpm install --frozen-lockfile
      - run: pnpm build

      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          packageManager: pnpm
          command: deploy
EOF
ok "deploy.yml"

# ---------- 12. Finalisation ----------
step "Génération des types Nuxt"
pnpm nuxt prepare >/dev/null 2>&1 || warn "nuxt prepare a échoué, relance 'pnpm nuxt prepare' à la main."

git add -A >/dev/null 2>&1 && git commit -m "chore: init Nuxt + Tailwind + GSAP + Cloudflare (pnpm)" >/dev/null 2>&1 \
  || warn "Commit initial non effectué (git non configuré ?)"

echo -e "\n${GREEN}🎉 Projet '$PROJECT_NAME' prêt !${NC}\n"
echo "  cd $PROJECT_NAME"
echo "  pnpm dev          # dev local  -> http://localhost:3000"
echo "  pnpm cf:login     # connexion Cloudflare (une seule fois)"
echo "  pnpm preview      # test dans le runtime Workers -> http://localhost:8787"
echo "  pnpm deploy:cf    # déploiement en prod"
