/**
 * SettingsPage — 设置页面（移动端）
 * 从 archived SettingsPanel 迁移，适配 PageStack 布局。
 */

import React, { useState, useEffect, useCallback, useRef } from 'react';
import { ArrowLeft, Key, Globe, Cpu, Brain, Eye, EyeOff, Check, AlertCircle, Loader2, Zap } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';
import { useConfigStore } from '../stores/config.store';
import type { AttitudeLevel } from '../shared/types';

const ATTITUDE_OPTIONS: ReadonlyArray<{ value: AttitudeLevel; label: string; description: string }> = [
  { value: 'doubao', label: '温柔', description: '多鼓励，少批评' },
  { value: 'yuesheng', label: '月笙', description: '平衡，有建议有肯定' },
  { value: 'sensei', label: '严厉', description: '严格指导，不留情面' },
  { value: 'direct', label: '尖锐', description: '直接指出问题' },
];

export const SettingsPage: React.FC<{ params?: Record<string, string> }> = () => {
  const pop = usePageStackStore(s => s.pop);

  const apiKey = useConfigStore(s => s.apiKey);
  const baseUrl = useConfigStore(s => s.baseUrl);
  const modelName = useConfigStore(s => s.modelName);
  const attitudeLevel = useConfigStore(s => s.attitudeLevel);
  const attitudeLocked = useConfigStore(s => s.attitudeLocked);
  const maxTokens = useConfigStore(s => s.maxTokens);
  const isLoading = useConfigStore(s => s.isLoading);
  const isConfigured = useConfigStore(s => s.isConfigured);
  const testStatus = useConfigStore(s => s.testStatus);
  const testError = useConfigStore(s => s.testError);
  const testResponseTime = useConfigStore(s => s.testResponseTime);
  const setApiKey = useConfigStore(s => s.setApiKey);
  const setBaseUrl = useConfigStore(s => s.setBaseUrl);
  const setModelName = useConfigStore(s => s.setModelName);
  const setAttitudeLevel = useConfigStore(s => s.setAttitudeLevel);
  const setMaxTokens = useConfigStore(s => s.setMaxTokens);
  const loadConfig = useConfigStore(s => s.loadConfig);
  const testConnection = useConfigStore(s => s.testConnection);

  const [localKey, setLocalKey] = useState(apiKey);
  const [localUrl, setLocalUrl] = useState(baseUrl);
  const [localModel, setLocalModel] = useState(modelName);
  const [showKey, setShowKey] = useState(false);
  const maxTokensTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  useEffect(() => {
    if (isLoading) {
      loadConfig().catch(e => {
        setSaveStatus('error');
        setErrorMsg(e instanceof Error ? e.message : '加载配置失败');
      });
    }
  }, [isLoading, loadConfig]);
  useEffect(() => setLocalKey(apiKey), [apiKey]);
  useEffect(() => setLocalUrl(baseUrl), [baseUrl]);
  useEffect(() => setLocalModel(modelName), [modelName]);

  const hasChanges = localKey !== apiKey || localUrl !== baseUrl || localModel !== modelName;

  const handleSave = useCallback(async () => {
    setSaveStatus('saving');
    setErrorMsg(null);
    try {
      if (localKey !== apiKey) await setApiKey(localKey);
      if (localUrl !== baseUrl) await setBaseUrl(localUrl);
      if (localModel !== modelName) await setModelName(localModel);
      setSaveStatus('success');
      setTimeout(() => setSaveStatus('idle'), 2000);
    } catch (e) {
      setSaveStatus('error');
      setErrorMsg(e instanceof Error ? e.message : '保存失败');
    }
  }, [localKey, localUrl, localModel, apiKey, baseUrl, modelName, setApiKey, setBaseUrl, setModelName]);
  const handleAttitudeChange = useCallback(async (level: AttitudeLevel) => {
    if (attitudeLocked) return;
    try { await setAttitudeLevel(level); }
    catch (e) { setErrorMsg(e instanceof Error ? e.message : '设置态度档位失败'); }
  }, [attitudeLocked, setAttitudeLevel]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
        </button>
        <h1 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>设置</h1>
      </header>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px' }}>
        {/* API 配置 */}
        <section style={{ marginBottom: 24 }}>
          <h2 style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 10 }}>
            API 配置
          </h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {/* API Key */}
            <div>
              <label style={{ fontSize: 12, color: 'var(--text-tertiary)', display: 'flex', alignItems: 'center', gap: 4, marginBottom: 4 }}>
                <Key size={12} strokeWidth={1.6} /> API Key
              </label>
              <div style={{ display: 'flex', gap: 4 }}>
                <input
                  type={showKey ? 'text' : 'password'}
                  value={localKey}
                  onChange={e => setLocalKey(e.target.value)}
                  placeholder="sk-..."
                  autoComplete="off"
                  spellCheck={false}
                  style={{
                    flex: 1, height: 38, borderRadius: 8, border: '1px solid var(--border)',
                    background: 'var(--bg-input)', padding: '0 12px',
                    fontSize: 13, color: 'var(--text-primary)', outline: 'none',
                  }}
                />
                <button
                  onClick={() => setShowKey(!showKey)}
                  aria-label={showKey ? '隐藏' : '显示'}
                  style={{
                    width: 38, height: 38, borderRadius: 8, border: '1px solid var(--border)',
                    background: 'var(--bg-input)', cursor: 'pointer',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}
                >
                  {showKey ? <EyeOff size={14} color="var(--text-tertiary)" /> : <Eye size={14} color="var(--text-tertiary)" />}
                </button>
              </div>
            </div>

            {/* Base URL */}
            <div>
              <label style={{ fontSize: 12, color: 'var(--text-tertiary)', display: 'flex', alignItems: 'center', gap: 4, marginBottom: 4 }}>
                <Globe size={12} strokeWidth={1.6} /> Base URL
              </label>
              <input
                value={localUrl}
                onChange={e => setLocalUrl(e.target.value)}
                placeholder="https://api.deepseek.com"
                spellCheck={false}
                style={{
                  width: '100%', height: 38, borderRadius: 8, border: '1px solid var(--border)',
                  background: 'var(--bg-input)', padding: '0 12px',
                  fontSize: 13, color: 'var(--text-primary)', outline: 'none',
                }}
              />
            </div>

            {/* Model */}
            <div>
              <label style={{ fontSize: 12, color: 'var(--text-tertiary)', display: 'flex', alignItems: 'center', gap: 4, marginBottom: 4 }}>
                <Cpu size={12} strokeWidth={1.6} /> 模型名称
              </label>
              <input
                value={localModel}
                onChange={e => setLocalModel(e.target.value)}
                placeholder="deepseek-v4-flash"
                spellCheck={false}
                style={{
                  width: '100%', height: 38, borderRadius: 8, border: '1px solid var(--border)',
                  background: 'var(--bg-input)', padding: '0 12px',
                  fontSize: 13, color: 'var(--text-primary)', outline: 'none',
                }}
              />
            </div>
          </div>
          {/* 保存 + 测试 */}
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <button
              onClick={handleSave}
              disabled={!hasChanges || saveStatus === 'saving'}
              style={{
                flex: 1, height: 38, borderRadius: 8, border: 'none',
                background: hasChanges && saveStatus !== 'saving' ? 'var(--accent)' : 'var(--bg-input)',
                color: hasChanges && saveStatus !== 'saving' ? 'var(--text-on-accent)' : 'var(--text-tertiary)',
                fontSize: 13, fontWeight: 500, cursor: hasChanges && saveStatus !== 'saving' ? 'pointer' : 'default',
              }}
            >
              {saveStatus === 'saving' ? '保存中…' : '保存配置'}
            </button>
            <button
              onClick={() => testConnection()}
              disabled={testStatus === 'testing' || !localKey}
              style={{
                flex: 1, height: 38, borderRadius: 8,
                border: '1px solid var(--border)', background: 'var(--bg-card)',
                color: testStatus === 'testing' || !localKey ? 'var(--text-tertiary)' : 'var(--text-primary)',
                fontSize: 13, fontWeight: 500, cursor: testStatus === 'testing' || !localKey ? 'default' : 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
              }}
            >
              {testStatus === 'testing' ? <Loader2 size={14} className="spin" /> : <Zap size={14} />}
              测试连接
            </button>
          </div>

          {/* 状态反馈 */}
          {saveStatus === 'success' && (
            <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--color-growth)' }}>
              <Check size={12} /> 已保存
            </div>
          )}
          {saveStatus === 'error' && errorMsg && (
            <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--error)' }}>
              <AlertCircle size={12} /> {errorMsg}
            </div>
          )}
          {testStatus === 'success' && (
            <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--color-growth)' }}>
              <Check size={12} /> 连接成功 ({testResponseTime}ms)
            </div>
          )}
          {testStatus === 'error' && (
            <div style={{ marginTop: 8, display: 'flex', alignItems: 'center', gap: 4, fontSize: 12, color: 'var(--error)' }}>
              <AlertCircle size={12} /> {testError || '连接失败'}
            </div>
          )}
          {isConfigured && saveStatus === 'idle' && !hasChanges && (
            <div style={{ marginTop: 8, fontSize: 12, color: 'var(--text-tertiary)' }}>
              配置已保存到本地
            </div>
          )}
        </section>
        {/* 态度档位 */}
        <section style={{ marginBottom: 24 }}>
          <h2 style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 4, display: 'flex', alignItems: 'center', gap: 4 }}>
            <Brain size={12} strokeWidth={1.6} /> 态度档位
          </h2>
          <p style={{ fontSize: 11, color: 'var(--text-tertiary)', marginBottom: 10 }}>
            影响 AI 反馈的鼓励/批评比例{attitudeLocked ? '（已锁定）' : ''}
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }} role="radiogroup" aria-label="态度档位">
            {ATTITUDE_OPTIONS.map(({ value, label, description }) => {
              const active = attitudeLevel === value;
              return (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  disabled={attitudeLocked}
                  onClick={() => handleAttitudeChange(value)}
                  style={{
                    display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                    padding: '12px 14px', borderRadius: 10,
                    border: active ? '1.5px solid var(--accent)' : '1px solid var(--border)',
                    background: active ? 'var(--accent-faint)' : 'var(--bg-card)',
                    cursor: attitudeLocked ? 'not-allowed' : 'pointer',
                    opacity: attitudeLocked ? 0.6 : 1,
                    textAlign: 'left', color: 'inherit', font: 'inherit',
                  }}
                >
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-primary)' }}>{label}</div>
                    <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>{description}</div>
                  </div>
                  {active && <Check size={16} color="var(--accent)" />}
                </button>
              );
            })}
          </div>
        </section>
        {/* 高级设置 */}
        <section>
          <h2 style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 10 }}>
            高级
          </h2>
          <div style={{
            padding: '12px 14px', borderRadius: 10,
            border: '1px solid var(--border)', background: 'var(--bg-card)',
          }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
              <span style={{ fontSize: 13, color: 'var(--text-primary)' }}>最大 Token</span>
              <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--accent)' }}>{maxTokens}</span>
            </div>
            <input
              type="range"
              min={1024}
              max={32768}
              step={1024}
              value={maxTokens}
              onChange={e => {
                const value = Number(e.target.value);
                // 滑块拖动防抖 300ms 再写入 store
                if (maxTokensTimerRef.current) clearTimeout(maxTokensTimerRef.current);
                maxTokensTimerRef.current = setTimeout(() => setMaxTokens(value), 300);
              }}
              style={{ width: '100%', accentColor: 'var(--accent)' }}
            />
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 4, fontSize: 10, color: 'var(--text-tertiary)' }}>
              <span>1024</span>
              <span>32768</span>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
};
