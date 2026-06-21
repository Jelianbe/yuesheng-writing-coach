/**
 * Writing content API client
 *
 * Loads and saves the main manuscript content for a project.
 */

import { apiCall } from "./base"

export interface ProjectContent {
  chapterId: string | null
  content: string
  updatedAt: string | null
  wordCount: number
}

export interface SaveContentResult {
  chapterId: string
  savedAt: string
  success: boolean
  wordCount: number
}

export const contentApi = {
  /**
   * Get the writing content for a project
   */
  async get(projectId: string): Promise<ProjectContent> {
    return (await apiCall(`/api/projects/${projectId}/content`)) as ProjectContent
  },

  /**
   * Save the writing content for a project
   */
  async save(projectId: string, content: string): Promise<SaveContentResult> {
    return (await apiCall(`/api/projects/${projectId}/content`, {
      method: "PUT",
      body: JSON.stringify({ content }),
    })) as SaveContentResult
  },
}
