---
name: supabase-multi-project-ops
description: Manage Kyle's multi-account, multi-project Supabase operations. Use when the user asks about Supabase CLI login, project/account mapping, db push/pull, migrations, link, secrets, project-ref, or DB access for any project listed in `~/.kyle-secrets/supabase/registry.toml`.
metadata:
  short-description: Safely operate Kyle's multi-project Supabase setup
---

# Supabase Multi Project Ops

Use the centralized secret layout in `~/.kyle-secrets/supabase/` instead of guessing from random `.env` files or relying on a stale CLI profile.

## Read First

1. Read `~/.kyle-secrets/supabase/registry.toml`.
2. Read the matching file in `accounts/`.
3. Read the matching file in `projects/`.
4. Read `~/.kyle-secrets/supabase/README.md` if command flow is unclear.

## Workflow

### 1) Identify the target project

Map the user's wording to a project entry in `registry.toml` before doing anything else.

Use these clues:
- project key (`mompick`, `donechoosing`, etc.)
- human label (`맘픽`, `돈추징`, etc.)
- repo path
- project ref

If the project is unclear, stop and ask.

### 2) Load the right secret pair

Use exactly one account file and one project file.

Example:

```bash
set -a
source ~/.kyle-secrets/supabase/accounts/chickenbreast-ky.env
source ~/.kyle-secrets/supabase/projects/mompick.env
set +a
cd "$SUPABASE_REPO_PATH"
```

### 3) Choose the command path by task type

For platform/account tasks:
- project list
- secrets list/set
- functions deploy
- org/project visibility checks

Use the account token from `SUPABASE_ACCESS_TOKEN`.

For DB/migration tasks:
- `supabase db push`
- `supabase migration list`
- `supabase db pull`
- `supabase db dump`
- `supabase link`

Prefer project DB info from `projects/*.env`.

### 4) Prefer DB URL over CLI profile magic

Default order:

1. `SUPABASE_DB_ADMIN_URL` for migrations/admin tools
2. `SUPABASE_DB_DIRECT_URL`
3. `SUPABASE_DB_PASSWORD` + `SUPABASE_PROJECT_REF`
3. Existing linked state only if it is already correct

Preferred examples:

```bash
supabase db push --db-url "$SUPABASE_DB_ADMIN_URL"
supabase migration list --linked -p "$SUPABASE_DB_PASSWORD"
supabase link --project-ref "$SUPABASE_PROJECT_REF" -p "$SUPABASE_DB_PASSWORD"
```

Do not assume named CLI profiles are reliable.

### 5) Respect pooler modes

- `SUPABASE_DB_APP_URL` is the default app-side URL.
- `SUPABASE_DB_POOLER_TRANSACTION_URL` is the default for temporary/serverless clients.
- `SUPABASE_DB_POOLER_SESSION_URL` is for persistent clients or IPv4-friendly app traffic.
- `SUPABASE_DB_DIRECT_URL` is the true direct connection string.
- `SUPABASE_DB_ADMIN_URL` is the practical admin default for Kyle's current machine. If direct fails due to IPv6/network issues, prefer the session pooler there while keeping the direct URL stored separately.

### 6) Stop on missing secrets

If any required value still starts with `TODO_`, stop and tell Kyle exactly what is missing.

Typical blockers:
- missing `SUPABASE_ACCESS_TOKEN`
- missing `SUPABASE_DB_PASSWORD`
- missing `SUPABASE_DB_ADMIN_URL`
- missing `SUPABASE_DB_DIRECT_URL`
- unknown `SUPABASE_ACCOUNT_ALIAS`

### 7) Secret hygiene

- Do not print secrets unless Kyle explicitly asks.
- When summarizing, mention file paths and variable names, not secret values.
- Do not delete legacy secret files without Kyle approval.
- When consolidating old files into the new structure, copy first and keep the original until Kyle approves cleanup.

## Practical Defaults

- Keep runtime app keys like `SUPABASE_SERVICE_ROLE_KEY` and `VITE_SUPABASE_ANON_KEY` inside each project's `.env.local` unless Kyle asks to centralize them.
- Keep ops/migration access in `~/.kyle-secrets/supabase/projects/*.env`.
- Treat `registry.toml` as the source of truth for the current account-project list.
- Do not hardcode a permanent project allowlist inside this skill. Update `registry.toml` when projects are added, removed, or renamed.
