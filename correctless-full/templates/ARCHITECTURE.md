# Architecture — {PROJECT_NAME}

> Replace {PROJECT_NAME} above and delete this instruction line.

## Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| API Router | `src/api/routes/` | HTTP endpoints. Auth middleware attached here. |
| Database Layer | `src/db/` | Postgres via Prisma ORM. No raw SQL outside this folder. |
| Auth Service | `src/auth/` | JWT generation, validation, refresh. User context injected into requests. |

> Replace the examples above with your project's actual components.

## Design Patterns

### PAT-001: {Pattern Name}
- {What the pattern is}
- {Where it's enforced}
- {What violates it}

> Example:
> ### PAT-001: Repository Pattern
> - All database queries go through repository structs in `src/db/repos/`
> - Never import database packages from HTTP handlers or service layer
> - Each entity gets its own repo file: `src/db/repos/user.ts`

## Conventions

- {Convention 1: e.g., "Config: always read from src/config.ts, never process.env directly"}
- {Convention 2: e.g., "Validation: Zod schemas at API boundaries only"}
- {Convention 3: e.g., "Logging: use src/lib/logger.ts, never console.log"}

## Known Limitations

- {Limitation 1: e.g., "No rate limiting on public endpoints (TODO)"}
- {Limitation 2: e.g., "File uploads stored locally, not S3 (fine for MVP)"}
