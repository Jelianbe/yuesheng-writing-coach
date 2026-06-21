import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import TiptapEditor from "../tiptap-editor"

describe("TiptapEditor", () => {
  it("renders the editor with the shadcn toolbar", () => {
    render(<TiptapEditor content="<p>Hello world</p>" onUpdate={vi.fn()} />)

    expect(screen.getByTitle("Bold")).toBeInTheDocument()
    expect(screen.getByTitle("Highlight")).toBeInTheDocument()
    expect(screen.getByTitle("Add link")).toBeInTheDocument()
    expect(screen.getByTitle("Code block")).toBeInTheDocument()
    expect(screen.getByText("Hello world")).toBeInTheDocument()
  })

  it("disables undo before any edits", () => {
    render(<TiptapEditor content="" onUpdate={vi.fn()} />)
    expect(screen.getByTitle("Undo")).toBeDisabled()
  })
})
