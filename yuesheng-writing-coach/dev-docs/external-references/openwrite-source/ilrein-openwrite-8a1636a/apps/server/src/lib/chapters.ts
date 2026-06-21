import type { projectTypeEnum, workTypeEnum } from "../db/schema/project"

type ProjectType = (typeof projectTypeEnum)[number]
type WorkType = (typeof workTypeEnum)[number]

const PROJECT_TYPE_TO_WORK_TYPE: Record<ProjectType, WorkType> = {
  novel: "novel",
  trilogy: "novel",
  series: "novel",
  short_story_collection: "short_story",
  graphic_novel: "graphic_novel",
  screenplay: "screenplay",
}

export function workTypeForProject(projectType: ProjectType): WorkType {
  return PROJECT_TYPE_TO_WORK_TYPE[projectType]
}

export function nextChapterTitle(existingCount: number): string {
  return `Chapter ${existingCount + 1}`
}

/**
 * Turn a client-supplied chapter ordering into order updates.
 * Returns null unless orderedIds is exactly the set of existing ids
 * (no missing entries, no extras, no duplicates).
 */
export function buildReorderUpdates(
  orderedIds: string[],
  existingIds: string[]
): { id: string; order: number }[] | null {
  if (orderedIds.length !== existingIds.length) {
    return null
  }

  const existing = new Set(existingIds)
  const seen = new Set<string>()

  for (const id of orderedIds) {
    if (!existing.has(id) || seen.has(id)) {
      return null
    }
    seen.add(id)
  }

  return orderedIds.map((id, index) => ({ id, order: index + 1 }))
}
