import {
  appendInteractionMessage,
  clearPendingDecision,
  createLLMClient,
  runAgentSession,
  type InteractionSession,
} from "@actalk/inkos-core";
import { persistProjectSession } from "./session-store.js";
import { buildPipelineConfig, loadConfig } from "../utils.js";

export async function processTuiAgentInput(params: {
  readonly projectRoot: string;
  readonly input: string;
  readonly session: InteractionSession;
  readonly activeBookId?: string;
  readonly onTextDelta?: (text: string) => void;
}) {
  const config = await loadConfig({ requireApiKey: false, projectRoot: params.projectRoot });
  const client = createLLMClient(config.llm);
  const pipeline = new (await import("@actalk/inkos-core")).PipelineRunner(
    buildPipelineConfig(config, params.projectRoot, { quiet: true }),
  );
  const userTimestamp = Date.now();
  const resolvedBookId = params.activeBookId ?? params.session.activeBookId ?? null;
  const initialMessages = params.session.messages
    .filter((message) => message.role === "user" || message.role === "assistant")
    .map((message) => ({ role: message.role, content: message.content }));

  let nextSession = appendInteractionMessage(clearPendingDecision({
    ...params.session,
    ...(resolvedBookId ? { activeBookId: resolvedBookId } : {}),
    currentExecution: {
      status: "planning",
      ...(resolvedBookId ? { bookId: resolvedBookId } : {}),
      ...(params.session.activeChapterNumber ? { chapterNumber: params.session.activeChapterNumber } : {}),
      stageLabel: "agent",
    },
  }), {
    role: "user",
    content: params.input,
    timestamp: userTimestamp,
  });

  const trimmedInput = params.input.trim();
  const actionSource = trimmedInput.startsWith("/") ? "slash" : "free-text";
  const requestedIntent = resolvedBookId && trimmedInput === "/write"
    ? "write_next"
    : !resolvedBookId && trimmedInput === "/create"
      ? "create_book"
      : undefined;

  const result = await runAgentSession(
    {
      sessionId: params.session.sessionId,
      bookId: resolvedBookId,
      sessionKind: resolvedBookId ? "book" : "book-create",
      actionSource,
      requestedIntent,
      language: config.language ?? "zh",
      pipeline,
      projectRoot: params.projectRoot,
      model: client._piModel
        ? client._piModel
        : { provider: config.llm.provider ?? "openai", modelId: config.llm.model },
      apiKey: client._apiKey,
      onEvent: (event: any) => {
        if (event.type === "message_update" && event.assistantMessageEvent?.type === "text_delta") {
          params.onTextDelta?.(event.assistantMessageEvent.delta);
        }
      },
    },
    params.input,
    initialMessages,
  );
  const createdBookId = extractCreatedBookId(result.messages);
  const activeBookId = createdBookId ?? resolvedBookId;

  if (result.responseText?.trim()) {
    const lastAssistant = result.messages.filter((message: any) => message.role === "assistant").pop() as { thinking?: string } | undefined;
    nextSession = appendInteractionMessage({
      ...nextSession,
      ...(activeBookId ? { activeBookId } : {}),
      currentExecution: {
        status: "completed",
        ...(activeBookId ? { bookId: activeBookId } : {}),
        ...(params.session.activeChapterNumber ? { chapterNumber: params.session.activeChapterNumber } : {}),
        stageLabel: "agent",
      },
    }, {
      role: "assistant",
      content: result.responseText,
      ...(lastAssistant?.thinking ? { thinking: lastAssistant.thinking } : {}),
      timestamp: userTimestamp + 1,
    });
  } else {
    nextSession = {
      ...nextSession,
      ...(activeBookId ? { activeBookId } : {}),
      currentExecution: {
        status: "completed",
        ...(activeBookId ? { bookId: activeBookId } : {}),
        ...(params.session.activeChapterNumber ? { chapterNumber: params.session.activeChapterNumber } : {}),
        stageLabel: "agent",
      },
    };
  }

  await persistProjectSession(params.projectRoot, nextSession);
  return {
    responseText: result.responseText,
    session: nextSession,
  };
}

function extractCreatedBookId(messages: ReadonlyArray<unknown>): string | undefined {
  for (const message of messages) {
    const details = (message as { details?: { kind?: string; bookId?: string } }).details;
    if (details?.kind === "book_created" && details.bookId) {
      return details.bookId;
    }
  }
  return undefined;
}
