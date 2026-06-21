import { describe, expect, it } from "vitest";
import { buildAgentSystemPrompt } from "../agent/agent-system-prompt.js";

describe("buildAgentSystemPrompt", () => {
  describe("mode isolation", () => {
    it("defaults no-book sessions to plain chat, not book creation", () => {
      const prompt = buildAgentSystemPrompt(null, "zh");
      expect(prompt).toContain("普通聊天助手");
      expect(prompt).toContain("这里不是自动生产入口");
      expect(prompt).toContain("propose_action");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover：");
      expect(prompt).not.toContain("play_start：");
      expect(prompt).not.toContain("architect");
    });

    it("defaults active-book sessions to book mode", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh");
      expect(prompt).toContain("当前正在处理书籍「my-book」");
      expect(prompt).toContain("sub_agent");
      expect(prompt).toContain("writer");
      expect(prompt).toContain("角色卡编辑走 write_truth_file");
      expect(prompt).toContain("roles/主要角色/<角色名>.md");
    });

    it("English plain chat also has no production tool instructions", () => {
      const prompt = buildAgentSystemPrompt(null, "en");
      expect(prompt).toContain("general chat assistant");
      expect(prompt).toContain("not an automatic production surface");
      expect(prompt).toContain("propose_action");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover:");
      expect(prompt).not.toContain("play_start:");
      expect(prompt).not.toContain("architect");
    });

    it("edit mode treats role cards as editable truth files", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh", "edit");
      expect(prompt).toContain("外部编辑助手");
      expect(prompt).toContain("角色卡也是可编辑设定文件");
      expect(prompt).toContain("roles/major/<name>.md");
      expect(prompt).toContain("write_truth_file");
    });

    it("requires self-contained proposed action instructions", () => {
      const zhPrompt = buildAgentSystemPrompt(null, "zh", "chat");
      const enPrompt = buildAgentSystemPrompt(null, "en", "chat");
      expect(zhPrompt).toContain("instruction 必须自包含");
      expect(zhPrompt).toContain("不要让下一条 session 依赖上一轮聊天上下文猜");
      expect(enPrompt).toContain("instruction must be self-contained");
      expect(enPrompt).toContain("Do not make the next session infer missing context");
    });

    it("distinguishes production actions from assisted Studio workflow actions", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "chat");
      expect(prompt).toContain("生产型动作");
      expect(prompt).toContain("辅助入口动作");
      expect(prompt).toContain("fanfic_init");
      expect(prompt).toContain("continuation_import");
      expect(prompt).toContain("spinoff_create");
      expect(prompt).toContain("style_imitation");
      expect(prompt).toContain("不能声称已经生成成品");
    });

    it("maps style analysis requests to the style-imitation workflow", () => {
      const zhPrompt = buildAgentSystemPrompt(null, "zh", "chat");
      const enPrompt = buildAgentSystemPrompt(null, "en", "chat");
      expect(zhPrompt).toContain("文风分析");
      expect(zhPrompt).toContain("先分析再仿写");
      expect(zhPrompt).toContain("必须调用 propose_action");
      expect(zhPrompt).toContain("仿写/文风分析/参考文风/模仿笔法=style_imitation");
      expect(zhPrompt).toContain("不要用普通文字追问书名、原文、父书路径或解释流程");
      expect(zhPrompt).toContain("番外/正典资料/不进入主线=spinoff_create");
      expect(enPrompt).toContain("style analysis");
      expect(enPrompt).toContain("analyze first then imitate");
      expect(enPrompt).toContain("you must call propose_action");
      expect(enPrompt).toContain("style imitation/style analysis/reference-style/prose mimicry=style_imitation");
      expect(enPrompt).toContain("Do not answer by asking for a title/source text/parent-book path");
      expect(enPrompt).toContain("side-story/spinoff/canon-materials=spinoff_create");
    });
  });

  describe("book-create mode", () => {
    it("gates long-form creation behind a confirmation proposal", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "book-create");
      expect(prompt).toContain("建书助手");
      expect(prompt).toContain("确认是否创建");
      expect(prompt).toContain("分阶段");
      expect(prompt).toContain("世界观与规则");
      expect(prompt).toContain("人称/比例/禁忌/节奏要求");
      expect(prompt).toContain("propose_action");
      expect(prompt).toContain("create_book");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("architect");
      expect(prompt).toContain("标题");
      expect(prompt).toContain("题材");
      expect(prompt).toContain("世界观");
      expect(prompt).toContain("主角");
      expect(prompt).toContain("核心冲突");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover");
      expect(prompt).not.toContain("play_start");
      expect(prompt).not.toContain("play_step");
    });

    it("runs architect only after book creation is confirmed", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "book-create", {
        actionSource: "button",
        requestedIntent: "create_book",
      });
      expect(prompt).toContain("sub_agent");
      expect(prompt).toContain("architect");
      expect(prompt).toContain("创建长篇");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("play_start");
    });

    it("English book-create mode is isolated from short and play before confirmation", () => {
      const prompt = buildAgentSystemPrompt(null, "en", "book-create");
      expect(prompt).toContain("book creation assistant");
      expect(prompt).toContain("propose_action");
      expect(prompt).not.toContain("agent=\"architect\"");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("play_start");
    });
  });

  describe("short mode", () => {
    it("gates short-fiction and cover production behind a confirmation proposal", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "short");
      expect(prompt).toContain("InkOS Short 助手");
      expect(prompt).toContain("propose_action");
      expect(prompt).toContain("short_run");
      expect(prompt).toContain("generate_cover");
      expect(prompt).toContain("让用户确认");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("architect");
      expect(prompt).not.toContain("play_step");
    });

    it("runs short_fiction_run only after short production is confirmed", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "short", {
        actionSource: "button",
        requestedIntent: "short_run",
      });
      expect(prompt).toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover：");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("play_start");
    });

    it("runs generate_cover only after cover generation is confirmed", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "short", {
        actionSource: "button",
        requestedIntent: "generate_cover",
      });
      expect(prompt).toContain("generate_cover");
      expect(prompt).toContain("不要重跑正文");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("play_start");
    });

    it("English short mode does not mention book-creation internals before confirmation", () => {
      const prompt = buildAgentSystemPrompt(null, "en", "short");
      expect(prompt).toContain("InkOS Short assistant");
      expect(prompt).toContain("propose_action");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("architect");
    });
  });

  describe("play mode", () => {
    it("gates new world start behind a confirmation proposal before a world exists", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "play", { playWorldExists: false });
      expect(prompt).toContain("InkOS Play 助手");
      expect(prompt).toContain("propose_action");
      expect(prompt).toContain("play_start");
      expect(prompt).toContain("propose_action 就是确认卡");
      expect(prompt).toContain("playStart.worldContract");
      expect(prompt).toContain("playStart.visualContract");
      expect(prompt).toContain("playStart.initialScene 是确认后第一眼展示给玩家的正文场面");
      expect(prompt).toContain("设定摘要放 premise/worldContract");
      expect(prompt).toContain("动作跳板放 suggestedActions");
      expect(prompt).toContain("不要擅自加等级、数值、RPG 面板或固定每回合时间");
      expect(prompt).toContain("不要为了让确认卡更完整而补具体年限");
      expect(prompt).toContain("用户说“刚入门”就保持刚入门");
      expect(prompt).toContain("不要先用普通文字整理一遍再等用户二次确认");
      expect(prompt).not.toContain("play_step：");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("architect");
    });

    it("exposes play_step, play_revise, and play_edit after a world exists", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "play", { playWorldExists: true });
      expect(prompt).toContain("InkOS Play 助手");
      expect(prompt).toContain("play_step");
      expect(prompt).toContain("play_revise");
      expect(prompt).toContain("play_edit");
      expect(prompt).toContain("世界契约");
      expect(prompt).toContain("角色/物件/规则卡");
      expect(prompt).toContain("不推进时间");
      expect(prompt).toContain("用 play_edit");
      expect(prompt).toContain("用 play_revise");
      expect(prompt).toContain("重做/换版/改上一条");
      expect(prompt).not.toContain("propose_action");
      expect(prompt).not.toContain("play_start：");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("generate_cover");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("architect");
    });

    it("runs play_start only after world start is confirmed", () => {
      const prompt = buildAgentSystemPrompt(null, "zh", "play", {
        actionSource: "button",
        requestedIntent: "play_start",
      });
      expect(prompt).toContain("play_start");
      expect(prompt).toContain("worldContract");
      expect(prompt).toContain("没有明确规则就留空");
      expect(prompt).not.toContain("play_step");
      expect(prompt).not.toContain("propose_action");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("sub_agent");
    });
  });

  describe("book mode", () => {
    it("contains active-book writing tools and no cross-mode production tools", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh", "book");
      expect(prompt).toContain("my-book");
      expect(prompt).toContain("sub_agent");
      expect(prompt).toContain("writer");
      expect(prompt).toContain("auditor");
      expect(prompt).toContain("reviser");
      expect(prompt).toContain("chapterWordCount");
      expect(prompt).toContain("chapterNumber");
      expect(prompt).toContain("anti-detect");
      expect(prompt).toContain("approvedOnly");
      expect(prompt).toContain("generate_cover");
      expect(prompt).toContain("read");
      expect(prompt).toContain("write_truth_file");
      expect(prompt).toContain("rename_entity");
      expect(prompt).toContain("patch_chapter_text");
      expect(prompt).toContain("grep");
      expect(prompt).toContain("ls");
      expect(prompt).toContain("outline/story_frame.md");
      expect(prompt).toContain("roles/major/<name>.md");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("play_start");
      expect(prompt).not.toContain("play_step");
      expect(prompt).not.toMatch(/agent="architect"/);
    });

    it("steers chapter rewrite to reviser instead of writer", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh", "book");
      expect(prompt).toContain("改 / 修订 / 重写第 N 章");
      expect(prompt).toContain("sub_agent(agent=\"reviser\", chapterNumber=N)");
      expect(prompt).toContain("writer 只会续写新的下一章");
      expect(prompt).toContain("不要用 writer");
    });

    it("forbids answering chapter-writing requests with raw chapter prose in chat", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh", "book");
      expect(prompt).toContain("不要在聊天回答里直接写章节正文");
      expect(prompt).toContain("不能输出“# 第 N 章”");
      expect(prompt).toContain("必须调用 sub_agent(agent=\"writer\")");
      expect(prompt).toContain("sub_agent 成功返回后，本轮直接结束");
    });

    it("English active-book prompt is also isolated", () => {
      const prompt = buildAgentSystemPrompt("novel", "en", "book");
      expect(prompt).toContain("working on book \"novel\"");
      expect(prompt).toContain("sub_agent");
      expect(prompt).toContain("generate_cover");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("play_start");
      expect(prompt).not.toMatch(/agent="architect"/);
    });
  });

  describe("edit mode", () => {
    it("contains deterministic edit tools but no production tools", () => {
      const prompt = buildAgentSystemPrompt("my-book", "zh", "edit");
      expect(prompt).toContain("外部编辑助手");
      expect(prompt).toContain("read");
      expect(prompt).toContain("write_truth_file");
      expect(prompt).toContain("rename_entity");
      expect(prompt).toContain("patch_chapter_text");
      expect(prompt).toContain("grep");
      expect(prompt).toContain("ls");
      expect(prompt).not.toContain("sub_agent");
      expect(prompt).not.toContain("generate_cover");
      expect(prompt).not.toContain("short_fiction_run");
      expect(prompt).not.toContain("play_start");
    });
  });

  describe("global output rules", () => {
    it("forbids emoji in Chinese and English prompts", () => {
      expect(buildAgentSystemPrompt(null, "zh", "chat")).toContain("不要使用表情符号");
      expect(buildAgentSystemPrompt(null, "en", "chat")).toContain("Do not use emoji");
    });

    it("forbids claiming side effects without successful tool execution", () => {
      expect(buildAgentSystemPrompt(null, "zh", "chat")).toContain("不要虚报工具执行结果");
      expect(buildAgentSystemPrompt(null, "en", "chat")).toContain("do not claim side effects without successful tool results");
    });

    it("treats tool calls as the answer instead of encouraging filler before tools", () => {
      expect(buildAgentSystemPrompt(null, "zh", "play", { playWorldExists: false })).toContain("工具调用本身就是回答");
      expect(buildAgentSystemPrompt(null, "zh", "play", { playWorldExists: false })).toContain("不要先写寒暄");
      expect(buildAgentSystemPrompt(null, "en", "play", { playWorldExists: false })).toContain("the tool call itself is the answer");
      expect(buildAgentSystemPrompt(null, "en", "play", { playWorldExists: false })).toContain("do not add filler");
    });
  });
});
