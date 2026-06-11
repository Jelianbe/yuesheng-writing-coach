/**
 * clipboard utility — 剪贴板操作
 */

export async function copyToClipboard(text: string): Promise<void> {
  await navigator.clipboard.writeText(text);
}
