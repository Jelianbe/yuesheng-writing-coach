# OpenWrite Feature Checklist

Working list of features we want, benchmarked against NovelCrafter (June 2026).
Ordered by priority within each section. Items marked `[x]` are live in production.

## Already shipped

- [x] BYOK AI providers — OpenRouter, OpenAI, Anthropic, Groq, Gemini, Cohere, Ollama (local)
- [x] Editor auto-save with real save status + word counts
- [x] AI chat sidebar with project context (title, genre, characters)
- [x] Insert AI responses into the editor at cursor
- [x] Story canvas (React Flow): acts/chapters/scenes/beats as nodes
- [x] Typed writing↔writing connections (story_flow, character_arc, setting, thematic, plot_thread)
- [x] Graph-aware AI draft generation (connected context: preceding scenes, characters, settings, lore, threads)
- [x] Text blocks per story element with inline editing + word-count rollup
- [x] Basic codex: characters, locations, lore, plot points (CRUD)
- [x] Email verification + password reset (Cloudflare Email Service)
- [x] Custom domain + AGPL + self-hostable on Cloudflare free tier

## Phase A — Minimum credible migration path

The set that lets a NovelCrafter/Word user actually switch.

- [ ] **Chapters & scenes manuscript structure** (issue #70)
  - [x] Chapter CRUD + reorder API on the existing work→chapter schema
  - [x] Chapter sidebar in the write page: create, rename, reorder, delete
  - [x] Per-chapter word counts; project total = sum of chapters
  - [x] Per-chapter auto-save with flush on chapter switch
  - [ ] Scene level within chapters
  - [ ] Grid/plan view: drag-and-drop acts → chapters → scenes
- [ ] **Scene beats → prose** (reuse the canvas generation endpoint)
  - [ ] Beat field per scene ("what happens here")
  - [ ] Generate button in the manuscript editor, not just the canvas
  - [ ] Codex + preceding-scene context, same as graph generation
- [ ] **Inline AI text actions** in the Tiptap editor
  - [ ] Select text → rewrite / expand / shorten / describe more
  - [ ] Custom prompt on selection
  - [ ] Diff-style preview before applying
- [ ] **Import** — .docx, Markdown, HTML (chapter detection on import)
- [ ] **Export** — Markdown first, then DOCX, EPUB (issue #72)
- [ ] **Persistent chat threads** (current sidebar chat is lost on refresh)
  - [ ] Thread storage per project
  - [ ] Selectable context: this scene / outline / whole novel
  - [ ] Extract from chat → codex entry or scene beat

## Phase B — Codex depth

- [ ] Automatic mention detection (highlight codex entries in prose, "find all occurrences")
- [ ] Aliases / nicknames per entry
- [ ] Custom fields, tags, and categories on codex entries
- [ ] Per-entry AI context control (always include / never include / auto)
- [ ] Auto-populate codex from scene text ("detect characters in this scene")
- [ ] One-click scene summarization (also feeds cheaper AI context)
- [ ] Progressions — track how an entity changes across the story
- [ ] Relations view (we already have graph connections — surface them in the codex UI)
- [ ] Mention timeline (where each entity appears across chapters)

## Phase C — AI customization ("Tinker" equivalent)

- [ ] Custom prompt library with variables and reusable components
- [ ] Per-task model picker (API already accepts `model`; needs UI)
- [ ] Prompt preview before sending
- [ ] Streaming responses (chat + generation currently wait for the full reply)
- [ ] Model parameters (temperature etc.) where providers support them

## Phase D — Revision & insight

- [ ] Scene snapshots / revision history with restore
- [ ] Writing sessions, streaks & goals (issue #74 — `writing_session` table exists, unused)
- [ ] Review analytics: character appearance heatmap, characters-per-scene
- [ ] Markers / plot-hole flags with timeline view

## Phase E — Organization & QoL

- [ ] Series support with shared codex (`work` table already models books-within-project)
- [ ] Scene labels / drafting status
- [ ] POV & tense settings per project/scene
- [ ] Focus mode (distraction-free fullscreen)
- [ ] Novel templates (Save the Cat, three-act, etc.)
- [ ] Snippets / scratch notes
- [ ] Scene archive (parked/alternative scenes)
- [ ] Real co-authoring / editor invitations (teams schema exists; no live collab)
- [ ] Mobile-friendly editing pass

## Testing
- [x] Unit/component tests (Vitest, web + server), auto-running in mprocs
- [x] E2E tests (Playwright): writer journey + mobile editor regression, CI job

## Our differentiators (lean in, they don't have these)

- Visual story graph with typed, semantic connections driving generation
- Open source (AGPL), self-hostable, no subscription — provider-rate AI costs
- Cloudflare-native: one Worker + D1, free-tier friendly
