import type { Editor } from "@tiptap/react"

/**
 * Tracks the currently mounted Tiptap editor so components outside the
 * editor tree (like the AI sidebar) can insert content at the cursor.
 */
let activeEditor: Editor | null = null

export function setActiveEditor(editor: Editor | null) {
  activeEditor = editor
}

export function getActiveEditor(): Editor | null {
  return activeEditor
}
