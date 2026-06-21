import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { Link } from "@tanstack/react-router"
import { Loader2, Sparkles, Trash2 } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { ApiError, api, type TextBlock } from "@/lib/api"

interface NodeWritingPanelProps {
  nodeId: string
  projectId: string
}

function TextBlockEditor({
  projectId,
  nodeId,
  block,
  index,
  onChanged,
}: {
  block: TextBlock
  index: number
  nodeId: string
  onChanged: () => void
  projectId: string
}) {
  const [value, setValue] = useState(block.content ?? "")

  const updateMutation = useMutation({
    mutationFn: async (content: string) =>
      await api.graph.updateTextBlock(projectId, nodeId, block.id, { content }),
    onSuccess: onChanged,
    onError: () => toast.error("Failed to save text block"),
  })

  const deleteMutation = useMutation({
    mutationFn: async () => await api.graph.deleteTextBlock(projectId, nodeId, block.id),
    onSuccess: onChanged,
    onError: () => toast.error("Failed to delete text block"),
  })

  return (
    <div className="space-y-2 rounded-lg border bg-muted/10 p-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Badge variant="outline">Block {index + 1}</Badge>
          <span className="text-muted-foreground text-xs">{block.wordCount || 0} words</span>
          {updateMutation.isPending && (
            <span className="text-muted-foreground text-xs">Saving…</span>
          )}
        </div>
        <Button
          className="h-7 w-7 p-0 text-muted-foreground hover:text-destructive"
          disabled={deleteMutation.isPending}
          onClick={() => deleteMutation.mutate()}
          size="sm"
          type="button"
          variant="ghost"
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>
      <Textarea
        className="min-h-[120px]"
        onBlur={() => {
          if (value !== (block.content ?? "")) {
            updateMutation.mutate(value)
          }
        }}
        onChange={(e) => setValue(e.target.value)}
        value={value}
      />
    </div>
  )
}

export function NodeWritingPanel({ projectId, nodeId }: NodeWritingPanelProps) {
  const queryClient = useQueryClient()
  const [newBlockContent, setNewBlockContent] = useState("")
  const [instructions, setInstructions] = useState("")
  const [needsProvider, setNeedsProvider] = useState(false)

  const { data: textBlocks = [], isLoading } = useQuery({
    queryKey: ["text-blocks", projectId, nodeId],
    queryFn: async () => await api.graph.listTextBlocks(projectId, nodeId),
  })

  const refresh = () => {
    queryClient.invalidateQueries({ queryKey: ["text-blocks", projectId, nodeId] })
    queryClient.invalidateQueries({ queryKey: ["graph-nodes", projectId] })
  }

  const createMutation = useMutation({
    mutationFn: async (content: string) =>
      await api.graph.createTextBlock(projectId, {
        storyNodeId: nodeId,
        content,
        orderIndex: textBlocks.length,
      }),
    onSuccess: () => {
      setNewBlockContent("")
      refresh()
    },
    onError: () => toast.error("Failed to add text block"),
  })

  const generateMutation = useMutation({
    mutationFn: async () =>
      await api.graph.generateDraft(projectId, nodeId, {
        instructions: instructions.trim() || undefined,
      }),
    onSuccess: (result) => {
      toast.success(`Draft generated (${result.wordCount} words, via ${result.provider})`)
      setInstructions("")
      refresh()
    },
    onError: (error) => {
      if (error instanceof ApiError && error.code === "no_provider") {
        setNeedsProvider(true)
        return
      }
      toast.error(error instanceof Error ? error.message : "Generation failed")
    },
  })

  return (
    <div className="space-y-5">
      {/* AI Generation */}
      <div className="space-y-3 rounded-lg border border-primary/20 bg-primary/5 p-3">
        <div className="flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" />
          <span className="font-medium text-sm">Generate a draft</span>
        </div>
        <p className="text-muted-foreground text-xs">
          Uses this element's connected characters, settings, lore, plot threads, and preceding
          story elements as context, plus any existing text below.
        </p>
        {needsProvider ? (
          <div className="space-y-2 text-sm">
            <p>No AI provider connected yet.</p>
            <Button asChild size="sm" variant="outline">
              <Link to="/dashboard/ai">Set up AI provider</Link>
            </Button>
          </div>
        ) : (
          <>
            <Textarea
              className="min-h-[60px]"
              onChange={(e) => setInstructions(e.target.value)}
              placeholder="Optional instructions, e.g. 'tense pacing, end on a reveal'"
              value={instructions}
            />
            <Button
              className="w-full"
              disabled={generateMutation.isPending}
              onClick={() => generateMutation.mutate()}
              size="sm"
              type="button"
            >
              {generateMutation.isPending ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Writing draft…
                </>
              ) : (
                <>
                  <Sparkles className="mr-2 h-4 w-4" /> Generate draft
                </>
              )}
            </Button>
          </>
        )}
      </div>

      {/* Existing text blocks */}
      {isLoading && <div className="py-4 text-center text-muted-foreground text-sm">Loading…</div>}
      {!isLoading && textBlocks.length === 0 && (
        <div className="rounded-lg border-2 border-dashed py-6 text-center text-muted-foreground text-sm">
          No writing yet. Generate a draft above or add a block below.
        </div>
      )}
      {textBlocks.map((block, index) => (
        <TextBlockEditor
          block={block}
          index={index}
          key={block.id}
          nodeId={nodeId}
          onChanged={refresh}
          projectId={projectId}
        />
      ))}

      {/* Add new block */}
      <div className="space-y-2">
        <Label className="font-medium text-sm" htmlFor="new-text-block">
          Add text block
        </Label>
        <Textarea
          className="min-h-[80px]"
          id="new-text-block"
          onChange={(e) => setNewBlockContent(e.target.value)}
          placeholder="Write content for this story element..."
          value={newBlockContent}
        />
        <Button
          className="w-full"
          disabled={!newBlockContent.trim() || createMutation.isPending}
          onClick={() => createMutation.mutate(newBlockContent)}
          size="sm"
          type="button"
          variant="outline"
        >
          {createMutation.isPending ? "Adding…" : "Add block"}
        </Button>
      </div>
    </div>
  )
}
