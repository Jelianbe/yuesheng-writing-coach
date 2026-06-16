/**
 * SettingsPanel — 设置面板基础版（V2-022）
 *
 * 功能：
 * - API Key / Base URL / Model / Temperature 内联配置
 * - 连接测试
 * - 主题切换（亮色/暗色）
 * - 全部配置通过 config.store 持久化
 */

import React, { useState, useCallback } from 'react';
import { Key, Globe, Thermometer, Cpu, CheckCircle, XCircle, Sun, Moon, Loader, Brain } from 'lucide-react';
import { useConfigStore } from '../../stores/config.store';
import styles from './settings.module.css';
import shared from '../profile/panel-shared.module.css';

/** 输入行组件 */
const ConfigField: React.FC<{
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  type?: string;
  icon?: React.ReactNode;
  secret?: boolean;
}> = ({ label, value, onChange, placeholder, type = 'text', icon, secret }) => (
  <div className={styles.configField}>
    <label className={styles.fieldRow}>
      {icon}
      {label}
    </label>
    <div className={`${shared.flexAlignCenter} ${shared.flexGap6}`}>
      <input
        type={secret ? 'password' : type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        className={styles.input}
      />
    </div>
  </div>
);

export const SettingsPanel: React.FC = () => {
  const apiKey = useConfigStore(s => s.apiKey);
  const baseUrl = useConfigStore(s => s.baseUrl);
  const modelName = useConfigStore(s => s.modelName);
  const temperature = useConfigStore(s => s.temperature);
  const testStatus = useConfigStore(s => s.testStatus);
  const testError = useConfigStore(s => s.testError);
  const testResponseTime = useConfigStore(s => s.testResponseTime);
  const setApiKey = useConfigStore(s => s.setApiKey);
  const setBaseUrl = useConfigStore(s => s.setBaseUrl);
  const setModelName = useConfigStore(s => s.setModelName);
  const setTemperature = useConfigStore(s => s.setTemperature);
  const testConnection = useConfigStore(s => s.testConnection);
  const attitudeLevel = useConfigStore(s => s.attitudeLevel);
  const setAttitudeLevel = useConfigStore(s => s.setAttitudeLevel);

  // 本地编辑状态（避免每次按键都触发 IPC 持久化）
  const [localKey, setLocalKey] = useState(apiKey);
  const [localUrl, setLocalUrl] = useState(baseUrl);
  const [localModel, setLocalModel] = useState(modelName);

  // 主题状态（从 localStorage 读取）
  const [isDark, setIsDark] = useState(() => {
    return document.documentElement.getAttribute('data-theme') === 'dark';
  });

  // 保存按钮：仅保存已修改的字段
  const handleSave = useCallback(async () => {
    if (localKey !== apiKey) await setApiKey(localKey);
    if (localUrl !== baseUrl) await setBaseUrl(localUrl);
    if (localModel !== modelName) await setModelName(localModel);
  }, [localKey, localUrl, localModel, apiKey, baseUrl, modelName, setApiKey, setBaseUrl, setModelName]);

  // 主题切换
  const toggleTheme = useCallback(() => {
    const next = !isDark;
    setIsDark(next);
    document.documentElement.setAttribute('data-theme', next ? 'dark' : 'light');
    localStorage.setItem('theme', next ? 'dark' : 'light');
  }, [isDark]);

  const hasChanges = localKey !== apiKey || localUrl !== baseUrl || localModel !== modelName;

  return (
    <div className={styles.scrollContainer}>
      {/* API 配置 */}
      <div>
        <div className={`${shared.sectionHeader} ${shared.flexAlignCenter}`} style={{ paddingBottom: 10 }}>
          API 配置
        </div>
        <div className={styles.fieldGroup}>
          <ConfigField
            label="API Key"
            value={localKey}
            onChange={setLocalKey}
            placeholder="sk-..."
            secret
            icon={<Key size={12} strokeWidth={1.6} />}
          />
          <ConfigField
            label="Base URL"
            value={localUrl}
            onChange={setLocalUrl}
            placeholder="https://api.example.com"
            icon={<Globe size={12} strokeWidth={1.6} />}
          />
          <ConfigField
            label="模型名称"
            value={localModel}
            onChange={setLocalModel}
            placeholder="model-name"
            icon={<Cpu size={12} strokeWidth={1.6} />}
          />
          {/* Temperature */}
          <div className={shared.flexCol} style={{ gap: 4 }}>
            <label className={styles.fieldRow}>
              <Thermometer size={12} strokeWidth={1.6} />
              Temperature
              <span className={shared.textTertiary}>({temperature.toFixed(1)})</span>
            </label>
            <input
              type="range"
              min="0"
              max="2"
              step="0.1"
              value={temperature}
              onChange={e => setTemperature(parseFloat(e.target.value))}
              className={styles.rangeInput}
              style={{ accentColor: 'var(--accent)' }}
            />
          </div>

          {/* 态度模式 */}
          <div className={shared.flexCol} style={{ gap: 4 }}>
            <label className={styles.fieldRow}>
              <Brain size={12} strokeWidth={1.6} />
              态度模式
            </label>
            <div className={`${shared.flexRow} ${shared.flexGap6}`}>
              {(['doubao', 'yuesheng'] as const).map((level) => (
                <button
                  key={level}
                  type="button"
                  onClick={() => setAttitudeLevel(level)}
                  aria-pressed={attitudeLevel === level}
                  aria-label={`态度模式：${level === 'doubao' ? '温和' : '严格'}`}
                  className={`${styles.segmentedBtn} ${attitudeLevel === level ? styles.segmentedBtnActive : ''}`}
                >
                  {level === 'doubao' ? '温和' : '严格'}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* 操作按钮组 */}
        <div className={styles.btnGroup}>
          {hasChanges && (
            <button
              onClick={handleSave}
              aria-label="保存配置"
              className={styles.saveBtn}
            >
              保存配置
            </button>
          )}
          <button
            onClick={testConnection}
            disabled={testStatus === 'testing'}
            aria-label={testStatus === 'testing' ? '测试连接中' : '测试连接'}
            className={`${styles.testBtn} ${testStatus === 'testing' ? styles.testBtnDisabled : ''}`}
            style={{ flex: hasChanges ? 1 : undefined }}
            onMouseEnter={e => { if (testStatus !== 'testing') e.currentTarget.style.borderColor = 'var(--accent)'; }}
            onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--border)'; }}
          >
            {testStatus === 'testing' ? (
              <><Loader size={12} strokeWidth={1.6} className="animate-spin" /> 测试中...</>
            ) : (
              '测试连接'
            )}
          </button>
        </div>

        {/* 测试结果 */}
        {testStatus === 'success' && (
          <div className={styles.testResult}>
            <CheckCircle size={12} strokeWidth={1.6} />
            连接成功 {testResponseTime ? `(${testResponseTime}ms)` : ''}
          </div>
        )}
        {testStatus === 'error' && testError && (
          <div className={styles.testResultError}>
            <XCircle size={12} strokeWidth={1.6} />
            {testError}
          </div>
        )}
      </div>

      {/* 分隔线 */}
      <div className={styles.divider} />

      {/* 主题切换 */}
      <div>
        <div className={`${shared.sectionHeader} ${shared.flexAlignCenter}`} style={{ paddingBottom: 10 }}>
          显示设置
        </div>
        <button
          onClick={toggleTheme}
          aria-label={isDark ? '切换到亮色模式' : '切换到暗色模式'}
          className={styles.themeBtn}
          onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.background = 'var(--bg-hover)'; }}
          onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--border-light)'; e.currentTarget.style.background = 'transparent'; }}
        >
          <span className={styles.themeRow}>
            {isDark ? <Moon size={14} strokeWidth={1.6} /> : <Sun size={14} strokeWidth={1.6} />}
            {isDark ? '暗色模式' : '亮色模式'}
          </span>
          <span
            className={styles.toggleTrack}
            style={{ background: isDark ? 'var(--accent)' : 'var(--border)' }}
          >
            <span
              className={styles.toggleThumb}
              style={{ left: isDark ? 18 : 2 }}
            />
          </span>
        </button>
        <div className={styles.hintText}>
          配置自动保存到本地存储
        </div>
      </div>
    </div>
  );
};
