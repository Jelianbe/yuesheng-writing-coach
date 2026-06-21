// Pure helpers for presenting a book's "truth" files in the sidebar as
// reader-facing content instead of raw structured/engineering text. Non-coder
// authors should never see YAML frontmatter, generator scaffolding, or
// deprecated compat-pointer prose — these helpers translate the on-disk format
// into friendly cards and clean prose.

export interface TruthFrontmatter {
  readonly protagonist?: { readonly name?: string; readonly personalityLock?: ReadonlyArray<string> };
  readonly genreLock?: { readonly primary?: string };
  readonly eraConstraints?: { readonly enabled?: boolean; readonly period?: string; readonly region?: string };
  readonly prohibitions?: ReadonlyArray<string>;
  readonly fanficMode?: "canon" | "au" | "ooc" | "cp";
}

export interface DisplayCard {
  readonly label: string;
  readonly values: ReadonlyArray<string>;
}

const FANFIC_LABELS: Record<string, string> = {
  canon: "原著向",
  au: "架空改编",
  ooc: "OOC",
  cp: "CP 向",
};

// Turn the structured frontmatter of story_frame.md into a few reader-friendly
// cards. Only story-meaningful fields surface; engineering/tuning fields
// (audit dimensions, fatigue words, numeric overrides, version) are omitted on
// purpose so the reader sees story facts, not generator config.
export function frontmatterToCards(fm: TruthFrontmatter | null | undefined): ReadonlyArray<DisplayCard> {
  if (!fm) return [];
  const cards: DisplayCard[] = [];
  const name = fm.protagonist?.name?.trim();
  if (name) cards.push({ label: "主角", values: [name] });
  const genre = fm.genreLock?.primary?.trim();
  if (genre) cards.push({ label: "题材", values: [genre] });
  const era = fm.eraConstraints;
  if (era?.enabled) {
    const eraValues = [era.period, era.region]
      .map((v) => v?.trim())
      .filter((v): v is string => Boolean(v));
    if (eraValues.length > 0) cards.push({ label: "时代背景", values: eraValues });
  }
  const prohibitions = (fm.prohibitions ?? []).map((p) => p.trim()).filter(Boolean);
  if (prohibitions.length > 0) cards.push({ label: "红线", values: prohibitions });
  if (fm.fanficMode) {
    cards.push({ label: "同人模式", values: [FANFIC_LABELS[fm.fanficMode] ?? fm.fanficMode] });
  }
  return cards;
}

// Drop the architect's structural delimiters that occasionally survive into a
// file body (=== SECTION: x ===, ---ROLE---, ---CONTENT---). These are
// scaffolding for the generator, never meaningful to a reader. Plain markdown
// horizontal rules (---) are left untouched.
export function stripStructuralMarkers(text: string): string {
  if (!text) return "";
  return text
    .split("\n")
    .filter(
      (line) =>
        !/^\s*===\s*SECTION:.*===\s*$/.test(line) && !/^\s*---(?:ROLE|CONTENT)---\s*$/.test(line),
    )
    .join("\n")
    .trim();
}

// The architect plans the outline with an "OKR recursive" method, so the
// generated story_frame / volume_map prose carries management jargon
// (各卷OKR（Objective + Key Results）, 全书Objective, KR1/KR2…). That's useful
// content wearing engineering clothes — relabel it to plain Chinese for the
// reader. Only touches Chinese documents so an English book's prose is left
// intact (no zh labels spliced into English text). Display-only; raw file is
// unchanged.
export function relabelOkrJargon(text: string): string {
  if (!text || !/[一-鿿]/.test(text)) return text;
  return text
    .replace(/各卷\s*OKR\s*[（(]\s*Objective\s*\+\s*Key\s*Results\s*[）)]/gi, "各卷目标与关键节点")
    .replace(/\bKR\s*(\d+)/gi, "关键结果$1")
    .replace(/Key\s*Results?/gi, "关键结果")
    .replace(/\bOKR\b/gi, "目标")
    .replace(/\s?Objective\b/g, "目标")
    .replace(/\bKR\b/gi, "关键结果");
}

// First non-empty prose paragraph of a body, for an at-a-glance overview. A
// leading markdown heading on the paragraph is dropped so the glance is prose.
export function firstParagraph(text: string): string {
  const stripped = stripStructuralMarkers(text);
  for (const chunk of stripped.split(/\n{2,}/)) {
    const withoutHeading = chunk.replace(/^\s*#{1,6}\s+[^\n]*\n?/, "").trim();
    if (withoutHeading) return withoutHeading;
  }
  return "";
}

export interface RoleRef {
  readonly path: string;
  readonly name: string;
  readonly tier: "major" | "minor";
}

// Parse a roles/<tier>/<name>.md truth path (zh or en locale dirs) into a
// character reference. Returns null for any non-role path.
export function roleFromPath(path: string): RoleRef | null {
  const m = path.match(/^roles\/(主要角色|次要角色|major|minor)\/(.+)\.md$/);
  if (!m) return null;
  const tier = m[1] === "主要角色" || m[1] === "major" ? "major" : "minor";
  return { path, name: m[2], tier };
}

// Friendly labels + display order for foundation truth files, covering both the
// Phase 5 outline/* layout and the pre-Phase-5 flat layout. Character files
// (roles/*, character_matrix.md) are intentionally absent — they belong to the
// character roster, not the foundation list. Files absent from this map are not
// shown in the foundation list.
export const FOUNDATION_FILE_LABELS: Record<string, string> = {
  "outline/story_frame.md": "故事基石",
  "outline/volume_map.md": "卷纲规划",
  "current_state.md": "当前状态",
  "pending_hooks.md": "伏笔池",
  "emotional_arcs.md": "情感弧线",
  "subplot_board.md": "支线进度",
  // Pre-Phase-5 flat layout — only reached for old books; new books tag these
  // (story_bible.md / book_rules.md) as legacy and they are filtered out.
  "story_bible.md": "世界观设定",
  "volume_outline.md": "卷纲规划",
  "book_rules.md": "叙事规则",
};

// --- current_state.md ---------------------------------------------------

// At book creation current_state.md holds only an engineering seed note
// (referencing the consolidator / roles/*.当前现状 / pending_hooks startChapter=0)
// that means nothing to a reader. The consolidator later APPENDS real state
// after each chapter, so we strip the seed note and report whether any real
// runtime state exists yet.
export function presentCurrentState(content: string): { readonly isEmpty: boolean; readonly body: string } {
  const body = content
    .split("\n")
    .filter((line) => !/建书时占位|Seeded at book creation|consolidator/.test(line))
    .join("\n")
    .trim();
  // After dropping the seed note, is there any real state text beyond the heading?
  const meaningful = body
    .replace(/^#{1,6}\s+.*$/gm, "")
    .replace(/^>\s*$/gm, "")
    .trim();
  return { isEmpty: meaningful.length === 0, body };
}

// --- emotional_arcs.md (and other runtime tables) -----------------------

// A markdown table seeded with only its header row (no data) reads as "empty"
// to a user. emotional_arcs.md is seeded this way at book creation and filled
// per-chapter during writing, so we detect the header-only state to show a
// friendly empty message instead of a blank table.
export function hasTableRows(md: string): boolean {
  const rows = md
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.startsWith("|") && !/^\|\s*-{2,}/.test(l));
  // rows = header + data rows (the | --- | separator is excluded); >1 ⇒ has data.
  return rows.length > 1;
}

// --- pending_hooks.md ----------------------------------------------------

export interface PendingHook {
  readonly id: string;
  readonly type: string; // 类型 — 主线伏笔 / 角色前置 / 情感线伏笔 …
  readonly content: string; // 备注 — the actual foreshadow / setup text
  readonly payoff: string; // 回收卷 — where it pays off
  readonly core: boolean; // 核心 — load-bearing hook
  readonly promoted?: boolean; // 升级 — true means live hook debt; false means seed pool
}

function splitTableRow(line: string): string[] {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
}

// pending_hooks.md is a 13-column tracking table. Only a few columns are
// reader-facing; parse the table by header name (robust to column reordering)
// and keep the meaningful ones so the UI can render browsable cards instead of
// an unreadable wide table.
export function parsePendingHooks(md: string): ReadonlyArray<PendingHook> {
  const rows = md.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("|"));
  if (rows.length < 2) return [];
  const header = splitTableRow(rows[0]);
  const colOf = (...names: string[]) => header.findIndex((h) => names.includes(h));
  const idIdx = colOf("hook_id", "id");
  const typeIdx = colOf("类型");
  const payoffIdx = colOf("回收卷");
  const coreIdx = colOf("核心");
  const promotedIdx = colOf("升级", "promoted");
  const contentIdx = colOf("备注");

  return rows
    .slice(1)
    .filter((line) => !/^\|\s*-{2,}/.test(line)) // drop the | --- | --- | separator
    .map(splitTableRow)
    .filter((cells) => cells.length === header.length)
    .map((cells) => ({
      id: idIdx >= 0 ? cells[idIdx] : "",
      type: typeIdx >= 0 ? cells[typeIdx] : "",
      content: contentIdx >= 0 ? cells[contentIdx] : "",
      payoff: payoffIdx >= 0 ? cells[payoffIdx] : "",
      core: coreIdx >= 0 && cells[coreIdx] === "是",
      promoted: promotedIdx >= 0 ? parsePromotedCell(cells[promotedIdx]) : undefined,
    }))
    .filter((hook) => hook.content.length > 0 || hook.id.length > 0);
}

function parsePromotedCell(cell: string | undefined): boolean | undefined {
  const normalized = (cell ?? "").trim().toLowerCase();
  if (!normalized) return undefined;
  if (/^(true|yes|y|是|核心|core|1|✓|✔|promoted|已升级)$/.test(normalized)) return true;
  if (/^(false|no|n|否|未升级|seed|0|✗|✘)$/.test(normalized)) return false;
  return undefined;
}

export const FOUNDATION_FILE_ORDER: ReadonlyArray<string> = [
  "outline/story_frame.md",
  "outline/volume_map.md",
  "story_bible.md",
  "volume_outline.md",
  "book_rules.md",
  "current_state.md",
  "pending_hooks.md",
  "emotional_arcs.md",
  "subplot_board.md",
];
