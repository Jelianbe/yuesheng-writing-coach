# OpenWrite

**Open-source, AI-powered writing platform for novelists, screenwriters, and creative writers. ✨📝**

OpenWrite helps you plan, organize, and write long-form fiction — with an AI assistant that runs on **your own API keys**. No subscription, no markup on tokens, no lock-in. Your manuscript lives in your database (or ours, or one you self-host).

**Try it:** [openwrite.iliareingold.com](https://openwrite.iliareingold.com)

## What works today

- ✍️ **Rich text editor with auto-save** — a distraction-light Tiptap editor that persists your manuscript as you type, with live word counts and per-project progress tracking
- 🤖 **AI writing assistant (bring your own key)** — chat with an assistant that knows your project's title, genre, and characters, then insert its suggestions straight into your manuscript. Supported providers:
  - OpenRouter (one key, hundreds of models — easiest start)
  - OpenAI, Anthropic, Groq, Gemini, Cohere
  - Ollama (fully local models, fully private)
- 📚 **Codex** — structured world-building: characters, locations, lore entries, and plot points, organized per project
- 🗂️ **Projects** — novels, trilogies, series, short story collections, screenplays; genre, status, and target word count tracking
- 🔐 **Auth & workspaces** — email/password accounts with personal workspaces; API keys are encrypted at rest (AES-GCM)

## In progress

| Feature | Status |
| --- | --- |
| Chapter & scene management | Planned next |
| Streaming AI responses | Planned next |
| Manuscript export (Markdown / DOCX / EPUB) | Planned |
| Story canvas (visual plotting) | Experimental |
| Real-time collaboration | Designed, not built |

Found a bug or want to influence what gets built? [Open an issue](https://github.com/ilrein/openwrite/issues).

## Why OpenWrite

- **Your keys, your costs.** Tools like Sudowrite resell AI tokens at a markup. OpenWrite talks to providers directly with your key — you pay provider rates, or nothing at all with local Ollama models.
- **Your words, your data.** AGPL-3.0 licensed and self-hostable on Cloudflare's free tier. No training on your manuscript, no vendor holding your novel hostage.
- **Built for fiction.** Characters, lore, and plot structure are first-class concepts, not folders of notes.

## Tech stack

TypeScript end to end: React 19 + TanStack Router + TailwindCSS/shadcn-ui on the front, Hono on Cloudflare Workers with D1 (SQLite) + Drizzle ORM on the back, Better Auth for authentication. Bun workspaces with [mprocs](https://github.com/pvolok/mprocs) for dev orchestration and Vitest for tests.

## Getting started

```bash
bun install
```

### Database setup

This project uses Cloudflare D1 (SQLite) with Drizzle ORM. Local development runs against a local D1 instance managed by `wrangler dev`.

1. Copy the example environment file and fill in the values (any random strings work locally):

```bash
cp apps/server/.dev.vars.example apps/server/.dev.vars
```

`apps/server/.dev.vars` needs `BETTER_AUTH_SECRET`, `BETTER_AUTH_URL`, `CORS_ORIGIN`, and `ENCRYPTION_KEY` (a base64-encoded 32-byte key, e.g. `openssl rand -base64 32`).

2. Apply the schema:

```bash
bun db:push
```

### Run it

```bash
bun dev
```

Open [http://localhost:3001](http://localhost:3001) for the web app. The API runs at [http://localhost:3000](http://localhost:3000).

## Self-hosting

OpenWrite deploys as a single Cloudflare Worker (API + static frontend) backed by a D1 database — comfortably within Cloudflare's free tier for personal use:

```bash
wrangler d1 create your-database        # then update apps/server/wrangler.jsonc
wrangler secret put BETTER_AUTH_SECRET  # plus BETTER_AUTH_URL, CORS_ORIGIN, ENCRYPTION_KEY
bun run deploy
```

## Project structure

```
openwrite/
├── apps/
│   ├── web/         # Frontend (React + TanStack Router)
│   ├── server/      # Hono REST API on Cloudflare Workers
│   └── docs/        # VitePress documentation
```

## Available scripts

- `bun dev` — start web + server in an mprocs TUI (db-studio and docs available as extra panes)
- `bun build` — build all applications
- `bun dev:web` / `bun dev:server` — start a single app
- `bun test` — run the Vitest suites (web + server)
- `bun quality` — type checking + linting (run before committing)
- `bun db:push` — push schema changes to the database
- `bun db:studio` — open the Drizzle Studio database UI
- `bun run deploy` — build and deploy to Cloudflare

## Contributing

Issues and PRs are welcome — the roadmap above is a good place to start, and the codebase is small enough to learn in an afternoon. Run `bun quality` before submitting.

## License

[AGPL-3.0](LICENSE.md)
