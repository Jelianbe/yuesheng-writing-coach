import React, { useState } from 'react';
import { registerWorkspace } from '../../../../registry/workspace-registry';
import styles from './index.module.css';

type AttitudeLevel = 'doubao' | 'yuesheng' | 'sensei';

const ATTITUDE_DOTS: { level: AttitudeLevel; color: string; title: string }[] = [
  { level: 'doubao', color: 'var(--color-attitude-doubao)', title: '豆包(温和鼓励)' },
  { level: 'yuesheng', color: 'var(--color-attitude-yuesheng)', title: '月笙如歌(专业平衡)' },
  { level: 'sensei', color: 'var(--color-attitude-sensei)', title: 'Sensei(直接挑战)' },
];

export const SettingsWorkspace: React.FC = () => {
  const [attitudeLevel, setAttitudeLevel] = useState<AttitudeLevel>('doubao');

  return (
    <div className={styles.wrap}>
      <h3 className={styles.title}>设置</h3>

      <div className={styles.section}>
        <div className={styles.label}>API Key</div>
        <input
          type="password"
          placeholder="sk-..."
          className={styles.input}
          onChange={e => console.log('api key:', e.target.value)}
        />
      </div>

      <div className={styles.section}>
        <div className={styles.label}>Base URL</div>
        <input
          defaultValue="https://api.deepseek.com"
          className={styles.input}
          onChange={e => console.log('base url:', e.target.value)}
        />
      </div>

      <div className={styles.label}>默认态度</div>
      <div className={styles.attRow}>
        {ATTITUDE_DOTS.map(dot => {
          const isActive = attitudeLevel === dot.level;
          return (
            <button
              key={dot.level}
              title={dot.title}
              className={styles.attDot}
              onClick={() => setAttitudeLevel(dot.level)}
              style={{
                borderColor: dot.color,
                backgroundColor: isActive ? dot.color : 'transparent',
                transform: isActive ? 'scale(1.1)' : 'scale(1)',
              }}
            />
          );
        })}
      </div>

      <button
        className={styles.saveBtn}
        onClick={() => console.log('save settings')}
      >
        保存
      </button>
    </div>
  );
};

// ADR-002: 自注册(默认不打开)
registerWorkspace({
  id: '__settings__',
  name: '设置',
  icon: '⚙',
  defaultOpen: false,
  component: () => import('./index').then(m => ({ default: m.SettingsWorkspace })),
});
