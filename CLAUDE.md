# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Is Paperclip

Paperclip is an open-source control plane for AI-agent companies. It orchestrates teams of AI agents with task management, org charts, budgets, governance, and cost control. Humans define goals; agents execute autonomously.

## Read Before Making Changes

Read these docs in order for context:

1. `doc/GOAL.md` — project mission
2. `doc/PRODUCT.md` — product requirements
3. `doc/SPEC-implementation.md` — V1 build contract (the concrete implementation target)
4. `doc/DEVELOPING.md` — development guide
5. `doc/DATABASE.md` — database information

`doc/SPEC.md` is long-horizon product context (not the current build target).

## Commands

```sh
pnpm install              # Install dependencies
pnpm dev                  # Start dev server (API + UI) with watch mode
pnpm dev:once             # Start dev server without watch mode
pnpm build                # Build all workspace packages
pnpm typecheck            # TypeScript type-check all packages (pnpm -r typecheck)
pnpm test:run             # Run all Vitest tests once
pnpm test                 # Run Vitest in watch mode
pnpm test:e2e             # Run Playwright e2e tests (headless)
pnpm db:generate          # Generate Drizzle migration after schema changes
pnpm db:migrate           # Apply pending migrations
pnpm check:tokens         # Check for forbidden tokens in source
```

Run a single Vitest test file:
```sh
npx vitest run path/to/file.test.ts
```

Run a single e2e test:
```sh
npx playwright test --config tests/e2e/playwright.config.ts tests/e2e/some-test.spec.ts
```

Full verification before hand-off:
```sh
pnpm -r typecheck && pnpm test:run && pnpm build
```
If anything cannot be run, explicitly report what was not run and why.

## Architecture

**Monorepo** using pnpm workspaces. TypeScript throughout. Node.js 20+, pnpm 9+.

### Workspace Packages

- **`server/`** — Express 5 REST API + WebSocket server. Routes in `server/src/routes/`, services in `server/src/services/`. Auth via `better-auth`. Logging via Pino.
- **`ui/`** — React 19 + Vite + Tailwind CSS 4 SPA. Served by the API server in dev. Pages in `ui/src/pages/`, shared components in `ui/src/components/`. Uses React Query for data fetching.
- **`cli/`** — CLI tool (`paperclipai`). Built as a single bundle via esbuild.
- **`packages/db/`** — Drizzle ORM schema (`src/schema/*.ts`), migrations, and DB client. Uses embedded PostgreSQL in dev (no setup needed), external Postgres in production.
- **`packages/shared/`** — Shared types, constants, Zod validators, and API path constants. Imported by server, UI, CLI, and adapters.
- **`packages/adapters/`** — Agent runtime adapters (Claude, Codex, Cursor, Gemini, OpenClaw, Pi, OpenCode). Each implements a standard interface.
- **`packages/adapter-utils/`** — Shared utilities for adapter implementations.
- **`packages/plugins/`** — Plugin SDK for third-party extensions.

### Key Patterns

- **Company-scoped isolation**: Every domain entity is scoped to a company. Routes and services must enforce company boundaries.
- **Contract synchronization**: Schema/API changes must be updated across all layers: `packages/db` → `packages/shared` → `server` → `ui`.
- **Control-plane invariants**: Single-assignee task model, atomic issue checkout, approval gates for governed actions, budget hard-stop auto-pause, activity logging for mutations.
- **Strategic docs**: Do not replace `doc/SPEC.md` or `doc/SPEC-implementation.md` wholesale unless asked. Prefer additive updates and keep them aligned.

### Database Change Workflow

1. Edit schema in `packages/db/src/schema/*.ts`
2. Export new tables from `packages/db/src/schema/index.ts`
3. Run `pnpm db:generate` (compiles schema first, then generates migration)
4. Run `pnpm -r typecheck` to validate

### Dev Environment

- Leave `DATABASE_URL` unset to use embedded PostgreSQL (auto-created, zero config)
- API + UI both served at `http://localhost:3100`
- Health check: `curl http://localhost:3100/api/health`
- Reset dev DB: `rm -rf data/pglite && pnpm dev`

## Contributing Rules

- **Lockfile policy**: Do not commit `pnpm-lock.yaml` in PRs. CI manages it.
- **PR format**: Include a "thinking path" tracing from project context to the specific change (see `CONTRIBUTING.md`).
- **Auth model**: Board access = full-control operator context. Agent access uses bearer API keys (`agent_api_keys`), hashed at rest. Agent keys must not access other companies.
- **API endpoints**: Apply company access checks, enforce actor permissions (board vs agent), write activity log entries for mutations, return consistent HTTP errors (`400/401/403/404/409/422/500`).
- **UI expectations**: Keep routes/nav aligned with available API surface. Use company selection context for company-scoped pages. Surface failures clearly; never silently ignore API errors.
- **Docs alignment**: New plan docs go in `doc/plans/` with `YYYY-MM-DD-slug.md` filenames.

## Definition of Done

A change is done when all are true:

1. Behavior matches `doc/SPEC-implementation.md`
2. Typecheck, tests, and build pass
3. Contracts are synced across db/shared/server/ui
4. Docs updated when behavior or commands change
