/**
 * Word counting for editor HTML content.
 * Strips tags and entities, then counts whitespace-separated words.
 */

const HTML_TAG_PATTERN = /<[^>]*>/g
const HTML_ENTITY_PATTERN = /&[#a-zA-Z0-9]+;/g
const WHITESPACE_PATTERN = /\s+/

export function countWordsInHtml(html: string): number {
  const text = html.replace(HTML_TAG_PATTERN, " ").replace(HTML_ENTITY_PATTERN, " ").trim()

  if (text.length === 0) {
    return 0
  }

  return text.split(WHITESPACE_PATTERN).length
}
