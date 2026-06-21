import type { Message, ToolExecution } from "../../store/chat/types";

const PLAY_TOOLS = new Set(["play_start", "play_step", "play_revise"]);

export interface PlayChoiceSet {
  readonly key: string;
  readonly choices: readonly string[];
}

function actionsFromExecution(exec: ToolExecution): string[] {
  if (!PLAY_TOOLS.has(exec.tool) || exec.status !== "completed") return [];
  const details = exec.details as { suggestedActions?: unknown } | undefined;
  return Array.isArray(details?.suggestedActions)
    ? details.suggestedActions.filter((a): a is string => typeof a === "string" && a.trim().length > 0)
    : [];
}

function choiceSetFromExecution(exec: ToolExecution, fallbackKey: string): PlayChoiceSet | null {
  const choices = actionsFromExecution(exec);
  if (choices.length === 0) return null;
  return {
    key: typeof exec.id === "string" && exec.id.trim() ? exec.id : fallbackKey,
    choices,
  };
}

export function latestPlayChoiceSet(messages: ReadonlyArray<Message>): PlayChoiceSet | null {
  for (let i = messages.length - 1; i >= 0; i--) {
    const parts = messages[i]?.parts ?? [];
    for (let p = parts.length - 1; p >= 0; p--) {
      const part = parts[p];
      if (part.type !== "tool") continue;
      const set = choiceSetFromExecution(part.execution, `message-${i}-part-${p}`);
      if (set) return set;
    }

    // Direct tool executions created by confirmed action buttons may be present
    // on the flat message before they are rehydrated into chronological parts.
    const toolExecutions = messages[i]?.toolExecutions ?? [];
    for (let t = toolExecutions.length - 1; t >= 0; t--) {
      const set = choiceSetFromExecution(toolExecutions[t], `message-${i}-execution-${t}`);
      if (set) return set;
    }
  }
  return null;
}

export function latestPlayChoices(messages: ReadonlyArray<Message>): string[] {
  return [...(latestPlayChoiceSet(messages)?.choices ?? [])];
}
