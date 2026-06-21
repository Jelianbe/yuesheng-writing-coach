export type SaveState = "idle" | "dirty" | "saving" | "saved" | "error"

function formatTime(isoDate: string): string {
  return new Date(isoDate).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
}

export function saveStatusText(state: SaveState, savedAt: string | null): string {
  switch (state) {
    case "dirty":
      return "Unsaved changes"
    case "saving":
      return "Saving…"
    case "error":
      return "Save failed — retrying on next edit"
    case "saved":
      return savedAt ? `Saved at ${formatTime(savedAt)}` : "Saved"
    default:
      return savedAt ? `Last saved at ${formatTime(savedAt)}` : "Not saved yet"
  }
}
