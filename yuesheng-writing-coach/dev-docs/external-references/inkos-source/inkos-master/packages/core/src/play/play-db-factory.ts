import { PlayDB } from "./play-db.js";
import { PlayFileDB, type PlayGraphSnapshot } from "./play-file-db.js";
import type { PlayReducerDB } from "./play-reducer.js";

export interface PlayGraphDB extends PlayReducerDB {
  readonly snapshot: () => PlayGraphSnapshot;
  readonly replaceWithSnapshot: (snapshot: PlayGraphSnapshot) => void;
  readonly close?: () => void;
}

export function createPlayDB(runDir: string): PlayGraphDB {
  try {
    return new PlayDB(runDir);
  } catch (error) {
    if (isMissingNodeSqliteError(error)) {
      return new PlayFileDB(runDir);
    }
    throw error;
  }
}

function isMissingNodeSqliteError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("node:sqlite") || message.includes("No such built-in module");
}
