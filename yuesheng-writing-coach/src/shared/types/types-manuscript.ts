// 作品与章节类型

/** 作品（manuscripts 表行映射） */
export interface Manuscript {
  id: string;
  title: string;
  description: string;
  genre: string;
  status: 'active' | 'archived';
  created_at: number;
  updated_at: number;
  sort_order: number;
}

/** 章节（chapters 表行映射） */
export interface Chapter {
  id: string;
  manuscript_id: string;
  title: string;
  content: string;
  word_count: number;
  sort_order: number;
  status: 'draft' | 'revising' | 'complete';
  created_at: number;
  updated_at: number;
}
