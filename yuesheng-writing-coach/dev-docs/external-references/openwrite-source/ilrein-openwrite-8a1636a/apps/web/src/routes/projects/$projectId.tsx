import { useQuery } from "@tanstack/react-query"
import { createFileRoute, Link, Outlet } from "@tanstack/react-router"
import { Sparkles } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { useHotkeys } from "react-hotkeys-hook"
import { AIChatContent } from "@/components/ai-chat-content"

import { ProjectSidebar } from "@/components/project-sidebar"

import { Button } from "@/components/ui/button"

import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { SidebarInset, SidebarProvider } from "@/components/ui/sidebar"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import WriteHeader from "@/components/write-header"
import { useIsMobile } from "@/hooks/use-mobile"
import { getActiveEditor } from "@/lib/active-editor"
import { api } from "@/lib/api"

export const Route = createFileRoute("/projects/$projectId")({
  component: WriteLayout,
})

function WriteLayout() {
  const { projectId } = Route.useParams()
  const isMobile = useIsMobile()
  // On mobile the assistant is a full-screen sheet, so it must not auto-open
  // over the editor; on desktop it's a docked sidebar that opens by default.
  const [rightSidebarOpen, setRightSidebarOpen] = useState(false)
  const userToggledRef = useRef(false)

  // The assistant is docked (open) on desktop and closed on mobile by default.
  // Track the viewport until the user explicitly toggles it.
  useEffect(() => {
    if (!userToggledRef.current) {
      setRightSidebarOpen(!isMobile)
    }
  }, [isMobile])

  const toggleSidebar = () => {
    userToggledRef.current = true
    setRightSidebarOpen((prev) => !prev)
  }

  // Keyboard shortcut to toggle AI assistant
  useHotkeys(
    "cmd+j, ctrl+j",
    () => {
      toggleSidebar()
    },
    {
      preventDefault: true,
      enableOnFormTags: false,
      enableOnContentEditable: false,
    }
  )

  const handleInsertText = (text: string) => {
    const editor = getActiveEditor()
    if (editor) {
      editor.chain().focus().insertContent(text).run()
    }
  }

  // Fetch project details
  const { data: project, isLoading } = useQuery({
    queryKey: ["project", projectId],
    queryFn: async () => await api.projects.get(projectId),
  })

  if (isLoading) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="animate-pulse">Loading project...</div>
      </div>
    )
  }

  if (!project) {
    return (
      <div className="flex h-screen items-center justify-center">
        <div className="text-center">
          <h2 className="mb-2 font-semibold text-2xl">Project not found</h2>
          <Link to="/dashboard/projects">Back to Projects</Link>
        </div>
      </div>
    )
  }

  return (
    <SidebarProvider>
      <div className="flex h-screen w-full">
        {/* Project Sidebar */}
        <ProjectSidebar projectId={projectId} />

        {/* Main Content Area */}
        <SidebarInset className="flex flex-1 flex-col">
          {/* Header */}
          <div className="flex h-16 items-center justify-between border-b bg-background/95 pr-6 backdrop-blur supports-[backdrop-filter]:bg-background/60">
            <WriteHeader
              breadcrumbs={[
                { label: "Projects", to: "/dashboard/projects" },
                { label: project.title },
              ]}
            />

            {/* AI Assistant Toggle */}
            <Tooltip>
              <TooltipTrigger asChild>
                <Button onClick={toggleSidebar} size="sm" variant="outline">
                  <Sparkles className="h-4 w-4" />
                  <span className="sr-only">Toggle AI Assistant</span>
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">
                <p>AI Assistant (⌘J)</p>
              </TooltipContent>
            </Tooltip>
          </div>

          {/* Page Content */}
          <main className="flex-1 overflow-auto">
            <Outlet />
          </main>
        </SidebarInset>

        {/* Right Sidebar - AI Assistant */}
        {isMobile ? (
          <Sheet onOpenChange={setRightSidebarOpen} open={rightSidebarOpen}>
            <SheetContent className="w-[18rem] bg-background p-0" side="right">
              <SheetHeader className="sr-only">
                <SheetTitle>AI Writing Assistant</SheetTitle>
                <SheetDescription>AI-powered writing help and suggestions</SheetDescription>
              </SheetHeader>
              <AIChatContent onInsertText={handleInsertText} projectId={projectId} />
            </SheetContent>
          </Sheet>
        ) : (
          rightSidebarOpen && (
            <div className="w-[18rem] border-l bg-background">
              <AIChatContent onInsertText={handleInsertText} projectId={projectId} />
            </div>
          )
        )}
      </div>
    </SidebarProvider>
  )
}
