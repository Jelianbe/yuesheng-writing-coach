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
import { Key, Globe, Thermometer, Cpu, CheckCircle, XCircle, Sun, Moon, Loader } from 'lucide-react';
import { useConfigStore } from '../../stores/config.store';

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

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
  <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
    <label style={{ fontSize: '0.72rem', fontWeight: 500, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: 4 }}>
      {icon}
      {label}
    </label>
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <input
        type={secret ? 'password' : type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          flex: 1,
          padding: '6px 10px',
          border: '1px solid var(--border)',
          borderRadius: 'var(--radius-sm)',
          background: 'var(--bg-input)',
          color: 'var(--text-primary)',
          fontFamily: 'var(--font-body)',
          fontSize: '0.82rem',
          outline: 'none',
          transition: `border-color 200ms ${EASE_OUT_QUART}`,
        }}
        onFocus={e => { e.currentTarget.style.borderColor = 'var(--accent)'; }}
        onBlur={e => { e.currentTarget.style.borderColor = 'var(--border)'; }}
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
    <div style={{
      display: 'flex',
      flexDirection: 'column',
      gap: 20,
      overflowY: 'auto',
      overflowX: 'hidden',
      padding: '4px 0',
      minHeight: 0,
      scrollbarWidth: 'thin',
    }}>
      {/* API 配置 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 10px' }}>
          API 配置
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
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
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            <label style={{ fontSize: '0.72rem', fontWeight: 500, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: 4 }}>
              <Thermometer size={12} strokeWidth={1.6} />
              Temperature
              <span style={{ color: 'var(--text-tertiary)', fontWeight: 400 }}>({temperature.toFixed(1)})</span>
            </label>
            <input
              type="range"
              min="0"
              max="2"
              step="0.1"
              value={temperature}
              onChange={e => setTemperature(parseFloat(e.target.value))}
              style={{
                width: '100%',
                accentColor: 'var(--accent)',
              }}
            />
          </div>
        </div>

        {/* 操作按钮组 */}
        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          {hasChanges && (
            <button
              onClick={handleSave}
              style={{
                flex: 1,
                padding: '6px 12px',
                border: '1px solid var(--accent)',
                borderRadius: 'var(--radius-sm)',
                background: 'var(--accent)',
                color: 'var(--text-on-accent)',
                fontSize: '0.78rem',
                cursor: 'pointer',
                fontFamily: 'var(--font-body)',
                fontWeight: 500,
                transition: `all 150ms ${EASE_OUT_QUART}`,
              }}
            >
              保存配置
            </button>
          )}
          <button
            onClick={testConnection}
            disabled={testStatus === 'testing'}
            style={{
              flex: hasChanges ? 1 : undefined,
              padding: '6px 12px',
              border: '1px solid var(--border)',
              borderRadius: 'var(--radius-sm)',
              background: 'transparent',
              color: 'var(--text-secondary)',
              fontSize: '0.78rem',
              cursor: testStatus === 'testing' ? 'not-allowed' : 'pointer',
              fontFamily: 'var(--font-body)',
              display: 'flex',
              alignItems: 'center',
              gap: 4,
              transition: `all 150ms ${EASE_OUT_QUART}`,
              opacity: testStatus === 'testing' ? 0.6 : 1,
            }}
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
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.72rem', color: 'var(--success)', marginTop: 6 }}>
            <CheckCircle size={12} strokeWidth={1.6} />
            连接成功 {testResponseTime ? `(${testResponseTime}ms)` : ''}
          </div>
        )}
        {testStatus === 'error' && testError && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.72rem', color: 'var(--error)', marginTop: 6 }}>
            <XCircle size={12} strokeWidth={1.6} />
            {testError}
          </div>
        )}
      </div>

      {/* 分隔线 */}
      <div style={{ height: '1px', background: 'var(--border-light)' }} />

      {/* 主题切换 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 10px' }}>
          显示设置
        </div>
        <button
          onClick={toggleTheme}
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            width: '100%',
            padding: '10px 12px',
            border: '1px solid var(--border-light)',
            borderRadius: 'var(--radius-md)',
            background: 'transparent',
            cursor: 'pointer',
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-body)',
            fontSize: '0.82rem',
            transition: `all 150ms ${EASE_OUT_QUART}`,
          }}
          onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.background = 'var(--bg-hover)'; }}
          onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--border-light)'; e.currentTarget.style.background = 'transparent'; }}
        >
          <span style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            {isDark ? <Moon size={14} strokeWidth={1.6} /> : <Sun size={14} strokeWidth={1.6} />}
            {isDark ? '暗色模式' : '亮色模式'}
          </span>
          <span style={{
            width: 36,
            height: 20,
            borderRadius: 10,
            background: isDark ? 'var(--accent)' : 'var(--border)',
            position: 'relative',
            transition: `background 200ms ${EASE_OUT_QUART}`,
          }}>
            <span style={{
              position: 'absolute',
              top: 2,
              left: isDark ? 18 : 2,
              width: 16,
              height: 16,
              borderRadius: '50%',
              background: '#fff',
              transition: `left 200ms ${EASE_OUT_QUART}`,
              boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
            }} />
          </span>
        </button>
        <div style={{ fontSize: '0.65rem', color: 'var(--text-tertiary)', marginTop: 8, padding: '0 2px' }}>
          配置自动保存到本地存储
        </div>
      </div>
    </div>
  );
};


