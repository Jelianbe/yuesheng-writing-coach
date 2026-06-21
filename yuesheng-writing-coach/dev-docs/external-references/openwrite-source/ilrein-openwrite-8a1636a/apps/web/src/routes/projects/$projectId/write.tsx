import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { createFileRoute } from "@tanstack/react-router"
import { useCallback, useEffect, useRef, useState } from "react"
import { ChapterList } from "@/components/chapter-list"
import { StatusBar } from "@/components/status-bar"
import TiptapEditor from "@/components/tiptap-editor"
import { Button } from "@/components/ui/button"
import { api } from "@/lib/api"
import { type SaveState, saveStatusText } from "@/lib/save-status"
import { countWordsInHtml } from "@/lib/word-count"

const AUTOSAVE_DELAY_MS = 1500

export const Route = createFileRoute("/projects/$projectId/write")({
  component: WriteInterface,
})

function WriteInterface() {
  const { projectId } = Route.useParams()
  const queryClient = useQueryClient()

  const { data: chapters = [], isLoading: chaptersLoading } = useQuery({
    queryKey: ["chapters", projectId],
    queryFn: async () => await api.chapters.list(projectId),
  })

  const [selectedChapterId, setSelectedChapterId] = useState<string | null>(null)

  // Select the first chapter once the list loads (or after deletion)
  useEffect(() => {
    if (chapters.length === 0) {
      setSelectedChapterId(null)
      return
    }
    if (!(selectedChapterId && chapters.some((ch) => ch.id === selectedChapterId))) {
      setSelectedChapterId(chapters[0].id)
    }
  }, [chapters, selectedChapterId])

  const { data: doc, isLoading: contentLoading } = useQuery({
    queryKey: ["chapter-content", projectId, selectedChapterId],
    queryFn: async () => {
      if (!selectedChapterId) {
        throw new Error("No chapter selected")
      }
      return await api.chapters.getContent(projectId, selectedChapterId)
    },
    enabled: Boolean(selectedChapterId),
  })

  const [wordCount, setWordCount] = useState(0)
  const [saveState, setSaveState] = useState<SaveState>("idle")
  const [savedAt, setSavedAt] = useState<string | null>(null)

  const pendingRef = useRef({ chapterId: "", content: "", dirty: false })
  const timerRef = useRef(0)

  // Seed word count and last-saved time from the loaded chapter
  useEffect(() => {
    if (doc) {
      setWordCount(doc.wordCount)
      setSavedAt(doc.updatedAt)
      setSaveState("idle")
    }
  }, [doc])

  const { mutate: saveContent } = useMutation({
    mutationFn: async ({ chapterId, content }: { chapterId: string; content: string }) =>
      await api.chapters.saveContent(projectId, chapterId, content),
    onSuccess: (result) => {
      setSavedAt(result.savedAt)
      setSaveState(pendingRef.current.dirty ? "dirty" : "saved")
      queryClient.invalidateQueries({ queryKey: ["chapters", projectId] })
      queryClient.invalidateQueries({ queryKey: ["project", projectId] })
    },
    onError: () => {
      pendingRef.current.dirty = true
      setSaveState("error")
    },
  })

  const handleEditorUpdate = useCallback(
    (content: string) => {
      if (!selectedChapterId) {
        return
      }
      pendingRef.current = { chapterId: selectedChapterId, content, dirty: true }
      setWordCount(countWordsInHtml(content))
      setSaveState("dirty")
      window.clearTimeout(timerRef.current)
      timerRef.current = window.setTimeout(() => {
        pendingRef.current.dirty = false
        setSaveState("saving")
        saveContent({
          chapterId: pendingRef.current.chapterId,
          content: pendingRef.current.content,
        })
      }, AUTOSAVE_DELAY_MS)
    },
    [selectedChapterId, saveContent]
  )

  // Flush unsaved changes when switching chapters or leaving the page
  // biome-ignore lint/correctness/useExhaustiveDependencies: selectedChapterId intentionally re-arms the cleanup so pending edits flush on chapter switch
  useEffect(
    () => () => {
      window.clearTimeout(timerRef.current)
      if (pendingRef.current.dirty && pendingRef.current.chapterId) {
        pendingRef.current.dirty = false
        api.chapters
          .saveContent(projectId, pendingRef.current.chapterId, pendingRef.current.content)
          .catch((error) => {
            console.error("Failed to save draft on exit:", error)
          })
      }
    },
    [projectId, selectedChapterId]
  )

  const createFirstChapter = useMutation({
    mutationFn: async () => await api.chapters.create(projectId),
    onSuccess: (result) => {
      queryClient.invalidateQueries({ queryKey: ["chapters", projectId] })
      setSelectedChapterId(result.id)
    },
  })

  if (chaptersLoading) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="animate-pulse text-muted-foreground">Loading your manuscript…</div>
      </div>
    )
  }

  return (
    <div className="flex h-full">
      <ChapterList
        chapters={chapters}
        onSelect={setSelectedChapterId}
        projectId={projectId}
        selectedChapterId={selectedChapterId}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        {chapters.length === 0 && (
          <div className="flex flex-1 flex-col items-center justify-center gap-3 text-center">
            <p className="text-muted-foreground">Every novel starts with a first chapter.</p>
            <Button
              disabled={createFirstChapter.isPending}
              onClick={() => createFirstChapter.mutate()}
              type="button"
            >
              Create Chapter 1
            </Button>
          </div>
        )}

        {chapters.length > 0 && selectedChapterId && (
          <>
            <div className="flex-1 overflow-auto">
              {contentLoading || !doc ? (
                <div className="flex h-full items-center justify-center">
                  <div className="animate-pulse text-muted-foreground">Loading chapter…</div>
                </div>
              ) : (
                <TiptapEditor
                  content={doc.content}
                  key={selectedChapterId}
                  onUpdate={handleEditorUpdate}
                  placeholder="Begin your story... Ask the AI assistant for help with characters, plot, or writing style."
                />
              )}
            </div>
            <StatusBar lastSavedText={saveStatusText(saveState, savedAt)} wordCount={wordCount} />
          </>
        )}
      </div>
    </div>
  )
}
