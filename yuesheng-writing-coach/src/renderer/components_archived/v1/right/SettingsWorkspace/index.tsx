/**
 * SettingsWorkspace — 设置工作区
 *
 * 使用 useConfigStore 显示当前配置信息：
 * API 模型、温度、最大 Token、基础 URL、态度档位。
 * 只读展示，配置修改通过 config.store 的 action。
 *
 * 用法:
 * ```tsx
 * <SettingsWorkspace />
 * ```
 */
import { useConfigStore } from '@/stores/config.store';
import styles from './index.module.css';

/** 态度档位中文映射 */
const ATTITUDE_LABEL: Record<string, string> = {
  doubao: '豆包模式',
  yuesheng: '月笙如歌',
  sensei: 'Sensei 先生',
};

export function SettingsWorkspace(): JSX.Element {
  const modelName = useConfigStore((s) => s.modelName);
  const temperature = useConfigStore((s) => s.temperature);
  const maxTokens = useConfigStore((s) => s.maxTokens);
  const baseUrl = useConfigStore((s) => s.baseUrl);
  const attitudeLevel = useConfigStore((s) => s.attitudeLevel);
  const isLoading = useConfigStore((s) => s.isLoading);

  if (isLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>加载配置中...</div>
      </div>
    );
  }

  const handleEmpty = (value: string): string =>
    value.trim().length > 0 ? value : '未设置';

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>配置信息</h3>
      </div>

      <div className={styles.content}>
        <div className={styles.configItem}>
          <span className={styles.configLabel}>模型名称</span>
          <span
            className={[
              styles.configValue,
              modelName.trim().length === 0 ? styles.configValueEmpty : '',
            ]
              .filter(Boolean)
              .join(' ')}
          >
            {handleEmpty(modelName)}
          </span>
        </div>

        <div className={styles.configItem}>
          <span className={styles.configLabel}>温度参数（Temperature）</span>
          <span className={styles.configValue}>{temperature}</span>
        </div>

        <div className={styles.configItem}>
          <span className={styles.configLabel}>最大 Token 数（Max Tokens）</span>
          <span className={styles.configValue}>{maxTokens}</span>
        </div>

        <div className={styles.configItem}>
          <span className={styles.configLabel}>API 基础 URL</span>
          <span
            className={[
              styles.configValue,
              baseUrl.trim().length === 0 ? styles.configValueEmpty : '',
            ]
              .filter(Boolean)
              .join(' ')}
          >
            {handleEmpty(baseUrl)}
          </span>
        </div>

        <div className={styles.configItem}>
          <span className={styles.configLabel}>态度档位</span>
          <span className={styles.configValue}>
            {ATTITUDE_LABEL[attitudeLevel] ?? attitudeLevel}
          </span>
        </div>
      </div>
    </div>
  );
}
