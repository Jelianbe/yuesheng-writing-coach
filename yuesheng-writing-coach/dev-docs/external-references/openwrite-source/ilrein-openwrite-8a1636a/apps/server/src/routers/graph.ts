import { OpenAPIHono } from "@hono/zod-openapi"
import { and, asc, eq, inArray, or } from "drizzle-orm"
import { z } from "zod"
import { db } from "../db"
import { graphConnection, graphNode, project, textBlock } from "../db/schema"
import { requireAuth, verifyProjectAccess } from "../middleware/auth"
import { isCompletionFailure, runCompletionForUser } from "./ai"

interface Env {
  BETTER_AUTH_SECRET: string
  BETTER_AUTH_URL: string
  CORS_ORIGIN: string
  ENCRYPTION_KEY: string
}

interface Variables {
  activeOrganization: {
    id: string
    name: string
    slug: string
  } | null
  session: {
    id: string
    userId: string
  }
  user: {
    id: string
    email: string
    name: string
  }
}

const app = new OpenAPIHono<{ Bindings: Env; Variables: Variables }>()

// Move regex to top level to avoid performance issues
const WORD_SPLIT_REGEX = /\s+/

function countWords(content: string | null | undefined): number {
  const trimmed = content?.trim()
  if (!trimmed) {
    return 0
  }
  return trimmed.split(WORD_SPLIT_REGEX).length
}

// Keep graphNode.wordCount in sync with the sum of its text blocks
async function syncNodeWordCount(nodeId: string): Promise<void> {
  const blocks = await db
    .select({ wordCount: textBlock.wordCount })
    .from(textBlock)
    .where(eq(textBlock.storyNodeId, nodeId))

  const total = blocks.reduce((sum, block) => sum + (block.wordCount ?? 0), 0)

  await db
    .update(graphNode)
    .set({ wordCount: total, updatedAt: new Date() })
    .where(eq(graphNode.id, nodeId))
}

// Zod schemas for validation
const CreateGraphNodeSchema = z.object({
  nodeType: z.enum(["story_element", "character", "location", "lore", "plot_thread"]),
  subType: z.string().optional(),
  title: z.string().min(1),
  description: z.string().optional(),
  positionX: z.number().default(0),
  positionY: z.number().default(0),
  visualProperties: z.string().optional(), // JSON string
  metadata: z.string().optional(), // JSON string
})

const CreateTextBlockSchema = z.object({
  storyNodeId: z.string(),
  content: z.string().optional(),
  orderIndex: z.number().default(0),
})

const CreateConnectionSchema = z.object({
  sourceNodeId: z.string(),
  targetNodeId: z.string(),
  connectionType: z.enum([
    "story_flow",
    "character_arc",
    "setting",
    "plot_thread",
    "thematic",
    "reference",
  ]),
  connectionStrength: z.number().min(1).max(5).default(1),
  visualProperties: z.string().optional(), // JSON string
  metadata: z.string().optional(),
})

// Apply auth middleware only to the graph namespace
app.use("/projects/*", requireAuth)
// Verify project access for all project-specific routes
app.use("/projects/:projectId/*", verifyProjectAccess)

// Get all graph nodes for a project
app.openapi(
  {
    method: "get",
    path: "/projects/{projectId}/graph/nodes",
    request: {
      params: z.object({
        projectId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              nodes: z.array(z.unknown()),
            }),
          },
        },
        description: "Graph nodes retrieved successfully",
      },
    },
  },
  async (c) => {
    const { projectId } = c.req.valid("param")

    const nodes = await db.select().from(graphNode).where(eq(graphNode.projectId, projectId))

    return c.json({ nodes })
  }
)

// Update graph node position
app.openapi(
  {
    method: "put",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/position",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: z.object({
              positionX: z.number(),
              positionY: z.number(),
            }),
          },
        },
      },
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
            }),
          },
        },
        description: "Node position updated successfully",
      },
    },
  },
  async (c) => {
    const { nodeId } = c.req.valid("param")
    const { positionX, positionY } = c.req.valid("json")

    const now = new Date()

    await db
      .update(graphNode)
      .set({
        positionX,
        positionY,
        updatedAt: now,
      })
      .where(eq(graphNode.id, nodeId))

    return c.json({ success: true })
  }
)

// Update a graph node's content fields
app.openapi(
  {
    method: "put",
    path: "/projects/{projectId}/graph/nodes/{nodeId}",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: z.object({
              title: z.string().min(1).optional(),
              description: z.string().optional(),
              subType: z.string().optional(),
              visualProperties: z.string().optional(), // JSON string
              metadata: z.string().optional(), // JSON string
            }),
          },
        },
      },
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
            }),
          },
        },
        description: "Graph node updated successfully",
      },
    },
  },
  async (c) => {
    const { projectId, nodeId } = c.req.valid("param")
    const updates = c.req.valid("json")

    await db
      .update(graphNode)
      .set({
        ...(updates.title === undefined ? {} : { title: updates.title }),
        ...(updates.description === undefined ? {} : { description: updates.description }),
        ...(updates.subType === undefined ? {} : { subType: updates.subType }),
        ...(updates.visualProperties === undefined
          ? {}
          : { visualProperties: updates.visualProperties }),
        ...(updates.metadata === undefined ? {} : { metadata: updates.metadata }),
        updatedAt: new Date(),
      })
      .where(and(eq(graphNode.id, nodeId), eq(graphNode.projectId, projectId)))

    return c.json({ success: true })
  }
)

// Create a new graph node
app.openapi(
  {
    method: "post",
    path: "/projects/{projectId}/graph/nodes",
    request: {
      params: z.object({
        projectId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: CreateGraphNodeSchema,
          },
        },
      },
    },
    responses: {
      201: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
              id: z.string(),
            }),
          },
        },
        description: "Graph node created successfully",
      },
    },
  },
  async (c) => {
    const { projectId } = c.req.valid("param")
    const nodeData = c.req.valid("json")

    const nodeId = crypto.randomUUID()
    const now = new Date()

    // Map camelCase API fields to snake_case database fields
    await db.insert(graphNode).values({
      id: nodeId,
      projectId,
      nodeType: nodeData.nodeType,
      subType: nodeData.subType,
      title: nodeData.title,
      description: nodeData.description,
      positionX: nodeData.positionX || 0,
      positionY: nodeData.positionY || 0,
      visualProperties: nodeData.visualProperties,
      metadata: nodeData.metadata,
      wordCount: 0, // Default for new nodes
      createdAt: now,
      updatedAt: now,
    })

    return c.json({ success: true, id: nodeId }, 201)
  }
)

// Get all text blocks for a story node
app.openapi(
  {
    method: "get",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/text-blocks",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              textBlocks: z.array(z.unknown()),
            }),
          },
        },
        description: "Text blocks retrieved successfully",
      },
    },
  },
  async (c) => {
    const { nodeId } = c.req.valid("param")

    const blocks = await db
      .select()
      .from(textBlock)
      .where(eq(textBlock.storyNodeId, nodeId))
      .orderBy(asc(textBlock.orderIndex), asc(textBlock.createdAt))

    return c.json({ textBlocks: blocks })
  }
)

// Create a text block for a story node
app.openapi(
  {
    method: "post",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/text-blocks",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: CreateTextBlockSchema,
          },
        },
      },
    },
    responses: {
      201: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
              id: z.string(),
            }),
          },
        },
        description: "Text block created successfully",
      },
    },
  },
  async (c) => {
    const blockData = c.req.valid("json")

    const blockId = crypto.randomUUID()
    const now = new Date()

    // Map camelCase API fields to proper database fields
    await db.insert(textBlock).values({
      id: blockId,
      storyNodeId: blockData.storyNodeId,
      content: blockData.content,
      orderIndex: blockData.orderIndex || 0,
      wordCount: countWords(blockData.content),
      createdAt: now,
      updatedAt: now,
    })

    await syncNodeWordCount(blockData.storyNodeId)

    return c.json({ success: true, id: blockId }, 201)
  }
)

// Update a text block
app.openapi(
  {
    method: "put",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/text-blocks/{blockId}",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
        blockId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: z.object({
              content: z.string().optional(),
              orderIndex: z.number().optional(),
            }),
          },
        },
      },
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
              wordCount: z.number(),
            }),
          },
        },
        description: "Text block updated successfully",
      },
    },
  },
  async (c) => {
    const { nodeId, blockId } = c.req.valid("param")
    const updates = c.req.valid("json")
    const wordCount = countWords(updates.content)

    await db
      .update(textBlock)
      .set({
        ...(updates.content === undefined ? {} : { content: updates.content, wordCount }),
        ...(updates.orderIndex === undefined ? {} : { orderIndex: updates.orderIndex }),
        updatedAt: new Date(),
      })
      .where(and(eq(textBlock.id, blockId), eq(textBlock.storyNodeId, nodeId)))

    await syncNodeWordCount(nodeId)

    return c.json({ success: true, wordCount })
  }
)

// Delete a text block
app.openapi(
  {
    method: "delete",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/text-blocks/{blockId}",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
        blockId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
            }),
          },
        },
        description: "Text block deleted successfully",
      },
    },
  },
  async (c) => {
    const { nodeId, blockId } = c.req.valid("param")

    await db
      .delete(textBlock)
      .where(and(eq(textBlock.id, blockId), eq(textBlock.storyNodeId, nodeId)))

    await syncNodeWordCount(nodeId)

    return c.json({ success: true })
  }
)

// Get all connections for a project
app.openapi(
  {
    method: "get",
    path: "/projects/{projectId}/graph/connections",
    request: {
      params: z.object({
        projectId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              connections: z.array(z.unknown()),
            }),
          },
        },
        description: "Graph connections retrieved successfully",
      },
    },
  },
  async (c) => {
    const { projectId } = c.req.valid("param")

    const connections = await db
      .select()
      .from(graphConnection)
      .where(eq(graphConnection.projectId, projectId))

    return c.json({ connections })
  }
)

// Create a connection between nodes
app.openapi(
  {
    method: "post",
    path: "/projects/{projectId}/graph/connections",
    request: {
      params: z.object({
        projectId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: CreateConnectionSchema,
          },
        },
      },
    },
    responses: {
      201: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
              id: z.string(),
            }),
          },
        },
        description: "Graph connection created successfully",
      },
    },
  },
  async (c) => {
    const { projectId } = c.req.valid("param")
    const connectionData = c.req.valid("json")

    const connectionId = crypto.randomUUID()
    const now = new Date()

    // Map camelCase API fields to proper database fields
    await db.insert(graphConnection).values({
      id: connectionId,
      projectId,
      sourceNodeId: connectionData.sourceNodeId,
      targetNodeId: connectionData.targetNodeId,
      connectionType: connectionData.connectionType,
      connectionStrength: connectionData.connectionStrength || 1,
      visualProperties: connectionData.visualProperties,
      metadata: connectionData.metadata,
      createdAt: now,
      updatedAt: now,
    })

    return c.json({ success: true, id: connectionId }, 201)
  }
)

// Delete a graph node
app.openapi(
  {
    method: "delete",
    path: "/projects/{projectId}/graph/nodes/{nodeId}",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
            }),
          },
        },
        description: "Graph node deleted successfully",
      },
    },
  },
  async (c) => {
    const { nodeId } = c.req.valid("param")

    // Delete associated text blocks first (cascade delete)
    await db.delete(textBlock).where(eq(textBlock.storyNodeId, nodeId))

    // Delete associated connections where this node is source or target
    await db.delete(graphConnection).where(eq(graphConnection.sourceNodeId, nodeId))
    await db.delete(graphConnection).where(eq(graphConnection.targetNodeId, nodeId))

    // Finally delete the node itself
    await db.delete(graphNode).where(eq(graphNode.id, nodeId))

    return c.json({ success: true })
  }
)

// ---------------------------------------------------------------------------
// AI generation for a story element node, using its graph connections as context

const GENERATION_SYSTEM_PROMPT = `You are a fiction ghostwriter for OpenWrite.
Write polished narrative prose for the requested story element, staying consistent with the provided characters, settings, lore, and preceding events.
Match the tone of any existing text. Output ONLY the prose passage — no preamble, no headings, no commentary.`

const TRUNCATE_DESCRIPTION = 300
const TRUNCATE_PREDECESSOR_TEXT = 1200
const TRUNCATE_EXISTING_TEXT = 2000
const MAX_PREDECESSORS = 3

type LoadedNode = typeof graphNode.$inferSelect

function describeNodes(label: string, nodes: LoadedNode[]): string[] {
  if (nodes.length === 0) {
    return []
  }
  const lines = [`${label}:`]
  for (const item of nodes) {
    const description = item.description
      ? ` — ${item.description.slice(0, TRUNCATE_DESCRIPTION)}`
      : ""
    lines.push(`- ${item.title}${description}`)
  }
  return lines
}

function parseNodeMetadata(metadata: string | null): Record<string, unknown> {
  if (!metadata) {
    return {}
  }
  try {
    return JSON.parse(metadata) as Record<string, unknown>
  } catch {
    return {}
  }
}

async function loadNodeText(nodeId: string, maxChars: number): Promise<string> {
  const blocks = await db
    .select({ content: textBlock.content })
    .from(textBlock)
    .where(eq(textBlock.storyNodeId, nodeId))
    .orderBy(asc(textBlock.orderIndex), asc(textBlock.createdAt))

  const combined = blocks
    .map((block) => block.content ?? "")
    .filter(Boolean)
    .join("\n\n")

  return combined.length > maxChars ? combined.slice(-maxChars) : combined
}

interface GenerationContext {
  characters: LoadedNode[]
  locations: LoadedNode[]
  lore: LoadedNode[]
  plotThreads: LoadedNode[]
  predecessors: { node: LoadedNode; text: string }[]
}

async function loadGenerationContext(
  projectId: string,
  nodeId: string
): Promise<GenerationContext> {
  const connections = await db
    .select()
    .from(graphConnection)
    .where(
      and(
        eq(graphConnection.projectId, projectId),
        or(eq(graphConnection.sourceNodeId, nodeId), eq(graphConnection.targetNodeId, nodeId))
      )
    )

  const connectedIds = [
    ...new Set(
      connections.flatMap((conn) =>
        [conn.sourceNodeId, conn.targetNodeId].filter((id) => id !== nodeId)
      )
    ),
  ]

  const connectedNodes =
    connectedIds.length > 0
      ? await db.select().from(graphNode).where(inArray(graphNode.id, connectedIds))
      : []
  const byId = new Map(connectedNodes.map((node) => [node.id, node]))

  const context: GenerationContext = {
    characters: [],
    locations: [],
    lore: [],
    plotThreads: [],
    predecessors: [],
  }

  const predecessorNodes: LoadedNode[] = []
  const bucketByNodeType: Record<string, LoadedNode[] | undefined> = {
    character: context.characters,
    location: context.locations,
    lore: context.lore,
    plot_thread: context.plotThreads,
  }

  for (const conn of connections) {
    const otherId = conn.sourceNodeId === nodeId ? conn.targetNodeId : conn.sourceNodeId
    const other = byId.get(otherId)
    if (!other) {
      continue
    }
    if (conn.connectionType === "story_flow") {
      // story_flow points source -> target; predecessors are sources into this node
      if (conn.targetNodeId === nodeId && predecessorNodes.length < MAX_PREDECESSORS) {
        predecessorNodes.push(other)
      }
      continue
    }
    bucketByNodeType[other.nodeType]?.push(other)
  }

  for (const predecessor of predecessorNodes) {
    context.predecessors.push({
      node: predecessor,
      text: await loadNodeText(predecessor.id, TRUNCATE_PREDECESSOR_TEXT),
    })
  }

  return context
}

function buildGenerationPrompt(options: {
  projectTitle: string
  projectGenre: string | null
  node: LoadedNode
  context: GenerationContext
  existingText: string
  instructions?: string
}): string {
  const { node, context } = options
  const metadata = parseNodeMetadata(node.metadata)
  const lines: string[] = []

  lines.push(
    `PROJECT: ${options.projectTitle}${options.projectGenre ? ` (${options.projectGenre})` : ""}`
  )
  lines.push("")
  lines.push(`STORY ELEMENT TO WRITE: ${node.title}${node.subType ? ` (${node.subType})` : ""}`)
  if (node.description) {
    lines.push(`Summary: ${node.description.slice(0, 600)}`)
  }
  for (const key of ["goals", "conflict", "notes"]) {
    const value = metadata[key]
    if (typeof value === "string" && value.trim()) {
      lines.push(`${key.toUpperCase()}: ${value.slice(0, TRUNCATE_DESCRIPTION)}`)
    }
  }

  lines.push(...describeNodes("CHARACTERS IN THIS ELEMENT", context.characters))
  lines.push(...describeNodes("SETTINGS", context.locations))
  lines.push(...describeNodes("LORE / WORLD RULES", context.lore))
  lines.push(...describeNodes("PLOT THREADS", context.plotThreads))

  for (const predecessor of context.predecessors) {
    lines.push("")
    lines.push(`WHAT HAPPENS BEFORE — ${predecessor.node.title}:`)
    lines.push(predecessor.text || predecessor.node.description || "(no content yet)")
  }

  if (options.existingText) {
    lines.push("")
    lines.push("EXISTING TEXT OF THIS ELEMENT (continue from here, do not repeat it):")
    lines.push(options.existingText)
  }

  lines.push("")
  if (options.instructions) {
    lines.push(`ADDITIONAL INSTRUCTIONS: ${options.instructions.slice(0, 1000)}`)
  }
  lines.push(
    options.existingText
      ? "Write the next passage (roughly 300-600 words) continuing this element."
      : "Write the opening passage (roughly 300-600 words) for this element."
  )

  return lines.join("\n")
}

const errorResponseSchema = z.object({
  error: z.string(),
  code: z.string().optional(),
})

const errorContent = {
  content: { "application/json": { schema: errorResponseSchema } },
  description: "Error",
}

// Generate a draft passage for a story element using its connected context
app.openapi(
  {
    method: "post",
    path: "/projects/{projectId}/graph/nodes/{nodeId}/generate",
    request: {
      params: z.object({
        projectId: z.string(),
        nodeId: z.string(),
      }),
      body: {
        content: {
          "application/json": {
            schema: z.object({
              instructions: z.string().max(2000).optional(),
              model: z.string().optional(),
            }),
          },
        },
      },
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
              blockId: z.string(),
              content: z.string(),
              wordCount: z.number(),
              provider: z.string(),
              model: z.string().nullable(),
            }),
          },
        },
        description: "Draft generated and saved as a text block",
      },
      400: errorContent,
      404: errorContent,
      412: errorContent,
      500: errorContent,
      502: errorContent,
    },
  },
  async (c) => {
    const { projectId, nodeId } = c.req.valid("param")
    const { instructions, model } = c.req.valid("json")
    const user = c.get("user")

    const node = await db
      .select()
      .from(graphNode)
      .where(and(eq(graphNode.id, nodeId), eq(graphNode.projectId, projectId)))
      .get()

    if (!node) {
      return c.json({ error: "Node not found" }, 404)
    }
    if (node.nodeType !== "story_element") {
      return c.json({ error: "Drafts can only be generated for story elements" }, 400)
    }

    const projectData = await db
      .select({ title: project.title, genre: project.genre })
      .from(project)
      .where(eq(project.id, projectId))
      .get()

    if (!projectData) {
      return c.json({ error: "Project not found" }, 404)
    }

    const [context, existingText] = await Promise.all([
      loadGenerationContext(projectId, nodeId),
      loadNodeText(nodeId, TRUNCATE_EXISTING_TEXT),
    ])

    const prompt = buildGenerationPrompt({
      projectTitle: projectData.title,
      projectGenre: projectData.genre,
      node,
      context,
      existingText,
      instructions,
    })

    const result = await runCompletionForUser({
      userId: user.id,
      env: c.env,
      system: GENERATION_SYSTEM_PROMPT,
      messages: [{ role: "user", content: prompt }],
      model,
    })

    if (isCompletionFailure(result)) {
      return c.json({ error: result.error, code: result.code }, result.status)
    }

    // Persist the draft as a new text block at the end of the node
    const existingBlocks = await db
      .select({ id: textBlock.id })
      .from(textBlock)
      .where(eq(textBlock.storyNodeId, nodeId))

    const blockId = crypto.randomUUID()
    const now = new Date()
    const wordCount = countWords(result.message)

    await db.insert(textBlock).values({
      id: blockId,
      storyNodeId: nodeId,
      content: result.message,
      orderIndex: existingBlocks.length,
      wordCount,
      createdAt: now,
      updatedAt: now,
    })

    await syncNodeWordCount(nodeId)

    return c.json(
      {
        success: true,
        blockId,
        content: result.message,
        wordCount,
        provider: result.provider,
        model: result.model,
      },
      200
    )
  }
)

// Delete a connection
app.openapi(
  {
    method: "delete",
    path: "/projects/{projectId}/graph/connections/{connectionId}",
    request: {
      params: z.object({
        projectId: z.string(),
        connectionId: z.string(),
      }),
    },
    responses: {
      200: {
        content: {
          "application/json": {
            schema: z.object({
              success: z.boolean(),
            }),
          },
        },
        description: "Graph connection deleted successfully",
      },
    },
  },
  async (c) => {
    const { connectionId } = c.req.valid("param")

    await db.delete(graphConnection).where(eq(graphConnection.id, connectionId))

    return c.json({ success: true })
  }
)

export default app
