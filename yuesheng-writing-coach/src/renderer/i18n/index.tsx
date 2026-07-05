/**
 * i18n 配置入口
 *
 * 使用 react-intl 提供国际化支持。
 * 当前仅支持中文（zh-CN），后续可扩展其他语言。
 *
 * 用法:
 *   在 App 入口包裹 <I18nProvider>:
 *     <I18nProvider>
 *       <App />
 *     </I18nProvider>
 *
 *   在组件中使用:
 *     const { formatMessage: t } = useIntl();
 *     <h1>{t({ id: 'app.title' })}</h1>
 */
import React from 'react';
import { IntlProvider } from 'react-intl';
import zhCNMessages from './zh-CN';

// 当前唯一支持的语言
const LOCALE = 'zh-CN';
const MESSAGES: Record<string, Record<string, string>> = {
  'zh-CN': zhCNMessages,
};

interface I18nProviderProps {
  children: React.ReactNode;
}

export function I18nProvider({ children }: I18nProviderProps): React.ReactElement {
  return (
    <IntlProvider locale={LOCALE} messages={MESSAGES[LOCALE] ?? {}} defaultLocale="zh-CN">
      {children}
    </IntlProvider>
  );
}

export { useIntl } from 'react-intl';
