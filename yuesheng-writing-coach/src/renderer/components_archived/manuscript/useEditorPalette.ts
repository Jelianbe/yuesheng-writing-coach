import { useEditorStore } from '../../stores/editor.store';
import { THEME_PALETTES, ThemePalette } from './manuscript.constants';

/** EditorTheme 到 THEME_PALETTES key 的映射 */
const THEME_KEY_MAP: Record<string, string> = {
  paper: 'warm-paper',
  sepia: 'sepia-tone',
  dark: 'dark-charcoal',
};

/** 根据当前主题配置计算完整的色板 */
export function useEditorPalette(): ThemePalette {
  const themeId = useEditorStore(s => s.theme);
  const customBgColor = useEditorStore(s => s.customBgColor);
  const customTextColor = useEditorStore(s => s.customTextColor);

  const paletteKey = THEME_KEY_MAP[themeId] ?? themeId;
  return paletteKey === 'custom'
    ? { ...THEME_PALETTES.custom, bg: customBgColor, text: customTextColor }
    : THEME_PALETTES[paletteKey as keyof typeof THEME_PALETTES];
}
