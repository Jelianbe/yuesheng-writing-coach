import { z } from "zod";
import { PlayModeSchema, type PlayMode } from "./session.js";

export const ActionSourceSchema = z.enum(["free-text", "button", "slash", "quick-action"]);
export type ActionSource = z.infer<typeof ActionSourceSchema>;

export const RequestedIntentSchema = z.enum([
  "create_book",
  "write_next",
  "short_run",
  "play_start",
  "play_step",
  "generate_cover",
  "edit_artifact",
  "fanfic_init",
  "continuation_import",
  "spinoff_create",
  "style_imitation",
]);
export type RequestedIntent = z.infer<typeof RequestedIntentSchema>;

export const CreateBookActionPayloadSchema = z.object({
  title: z.string().min(1).optional(),
  genre: z.string().min(1).optional(),
  platform: z.enum(["tomato", "qidian", "feilu", "other"]).optional(),
  language: z.enum(["zh", "en"]).optional(),
  targetChapters: z.number().int().min(1).optional(),
  chapterWordCount: z.number().int().min(1).optional(),
}).strict();

export const ShortRunActionPayloadSchema = z.object({
  direction: z.string().min(1).optional(),
  reference: z.string().min(1).optional(),
  storyId: z.string().min(1).optional(),
  chapters: z.number().int().min(12).max(18).optional(),
  charsPerChapter: z.number().int().min(900).max(1200).optional(),
  cover: z.boolean().optional(),
}).strict();

export const PlayStartActionPayloadSchema = z.object({
  title: z.string().min(1).optional(),
  premise: z.string().min(1).optional(),
  worldContract: z.string().min(1).optional(),
  visualContract: z.string().min(1).optional(),
  mode: PlayModeSchema.optional(),
  initialScene: z.string().min(1).optional(),
  suggestedActions: z.array(z.string().min(1)).min(1).max(4).optional(),
}).strict();

export const GenerateCoverActionPayloadSchema = z.object({
  title: z.string().min(1).optional(),
  intro: z.string().min(1).optional(),
  sellingPoints: z.string().min(1).optional(),
  coverPrompt: z.string().min(1).optional(),
  outputDir: z.string().min(1).optional(),
}).strict();

export const ActionPayloadSchema = z.object({
  createBook: CreateBookActionPayloadSchema.optional(),
  shortRun: ShortRunActionPayloadSchema.optional(),
  playStart: PlayStartActionPayloadSchema.optional(),
  generateCover: GenerateCoverActionPayloadSchema.optional(),
}).strict();

export type ActionPayload = z.infer<typeof ActionPayloadSchema>;

export function normalizeActionSource(value: unknown): ActionSource {
  if (value === undefined || value === null || value === "") return "free-text";
  return ActionSourceSchema.parse(value);
}

export function normalizeRequestedIntent(value: unknown): RequestedIntent | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return RequestedIntentSchema.parse(value);
}

export function normalizeActionPayload(value: unknown): ActionPayload | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return ActionPayloadSchema.parse(value);
}

export function normalizePlayMode(value: unknown): PlayMode | undefined {
  if (value === undefined || value === null || value === "") return undefined;
  return PlayModeSchema.parse(value);
}

const INCOMPLETE_PLAY_SCENE_SUFFIX =
  /(?:叫|是|为|在|向|把|将|和|与|或|但|却|因为|如果|当|等|、|，|：|；|——|“|‘|《|（|\()$/u;

export function isUsablePlayInitialScene(value: string | undefined): boolean {
  const text = value?.trim();
  if (!text) return false;
  if (text.length < 12) return false;
  if (INCOMPLETE_PLAY_SCENE_SUFFIX.test(text)) return false;
  return true;
}

export function isWriteNextInstruction(
  instruction: string,
  options: { readonly allowSlashWrite?: boolean } = {},
): boolean {
  const trimmed = instruction.trim();
  const pattern = options.allowSlashWrite
    ? /^(\/write|continue|继续|继续写|写下一章|write next|下一章|再来一章)$/i
    : /^(continue|继续|继续写|写下一章|write next|下一章|再来一章)$/i;
  return pattern.test(trimmed);
}

export function isExplicitWriteChapterCommand(instruction: string): boolean {
  const trimmed = instruction.trim();
  if (!trimmed) return false;

  const zhWriteChapter =
    /^(?:请|帮我|麻烦|现在|直接|开始|继续|接着|再)?\s*(?:写|续写|创作|生成)(?:出|一下)?\s*(?:第?\s*[一二三四五六七八九十百千万\d]+\s*章|下一章|一章|正文|章节)(?:\s|[，。,.！!？?；;：:]|$)/.test(trimmed);
  if (zhWriteChapter) return true;

  return /^(?:please\s+)?(?:write|continue|draft|generate)\s+(?:the\s+)?(?:next\s+)?chapter(?:\s+\d+|\s+one)?\b/i.test(trimmed);
}
