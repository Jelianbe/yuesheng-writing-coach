import { Highlight } from "@tiptap/extension-highlight"
import { HorizontalRule } from "@tiptap/extension-horizontal-rule"
import { Image } from "@tiptap/extension-image"
import { TaskItem, TaskList } from "@tiptap/extension-list"
import Placeholder from "@tiptap/extension-placeholder"
import { Subscript } from "@tiptap/extension-subscript"
import { Superscript } from "@tiptap/extension-superscript"
import { TextAlign } from "@tiptap/extension-text-align"
import { Typography } from "@tiptap/extension-typography"
import { Selection } from "@tiptap/extensions"
import { EditorContent, useEditor } from "@tiptap/react"
import { StarterKit } from "@tiptap/starter-kit"
import { useEffect } from "react"
import { EditorToolbar } from "@/components/editor-toolbar"
import { setActiveEditor } from "@/lib/active-editor"

interface TiptapEditorProps {
  content?: string
  onUpdate?: (content: string) => void
  placeholder?: string
}

export default function TiptapEditor({
  content = "",
  onUpdate,
  placeholder = "Write something beautiful...",
}: TiptapEditorProps) {
  const editor = useEditor({
    shouldRerenderOnTransaction: true,
    immediatelyRender: true,
    extensions: [
      StarterKit.configure({
        horizontalRule: false,
        dropcursor: { color: "var(--primary)" },
        bold: {
          HTMLAttributes: {
            class: "font-bold",
          },
        },
        italic: {
          HTMLAttributes: {
            class: "italic",
          },
        },
        strike: {
          HTMLAttributes: {
            class: "line-through",
          },
        },
        code: {
          HTMLAttributes: {
            class: "rounded-md bg-muted px-[0.3rem] py-[0.2rem] font-mono text-sm",
          },
        },
        underline: {
          HTMLAttributes: {
            class: "underline",
          },
        },
        link: {
          openOnClick: false,
          HTMLAttributes: {
            class: "text-primary underline underline-offset-4",
          },
        },
      }),
      Selection,
      Image.configure({ allowBase64: true }),
      HorizontalRule,
      TextAlign.configure({ types: ["heading", "paragraph"] }),
      Typography,
      Highlight.configure({ multicolor: true }),
      Subscript,
      Superscript,
      TaskList,
      TaskItem.configure({ nested: true }),
      Placeholder.configure({
        placeholder,
      }),
    ],
    content,
    onUpdate: ({ editor: editorInstance }) => {
      const html = editorInstance.getHTML()
      onUpdate?.(html)
    },
    editorProps: {
      attributes: {
        class: "focus:outline-none min-h-full p-6",
      },
    },
  })

  // Expose the editor so the AI sidebar can insert text at the cursor
  useEffect(() => {
    setActiveEditor(editor)
    return () => setActiveEditor(null)
  }, [editor])

  if (!editor) {
    return <div className="animate-pulse">Loading editor...</div>
  }

  return (
    <div className="tiptap-editor-container flex h-full w-full flex-col bg-background">
      <EditorToolbar editor={editor} />

      <button
        aria-label="Text editor content area"
        className="tiptap-editor-content h-full flex-1 cursor-text overflow-auto text-left"
        onClick={() => {
          if (editor && !editor.isFocused) {
            editor.commands.focus("end")
          }
        }}
        type="button"
      >
        <EditorContent className="h-full" editor={editor} />
      </button>
    </div>
  )
}
