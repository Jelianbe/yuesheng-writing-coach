/**
 * SettingsPanel — 设置面板 (RWR-P0-6 重写版)
 *
 * 按 R-007 规格 + 用户决策: 重写为符合规格 DoD 的实现
 * 规格要求:
 *   - API Key 配置 (仅 main process 处理, R-029)
 *   - 态度档位默认偏好
 *
 * 与 V2-022 版本差异:
 *   - 删除温度滑块(RWR-P0-6 规格未要求)
 *   - 删除连接测试按钮(规格未要求)
 *   - 删除主题切换(规格未要求)
 *   - attitude 3 态(doubao / yuesheng / direct, 温柔 / 月笙 / 尖锐)
 *     原版只显示 2 态
 *   - 内联样式 → CSS Module
 *   - 保留密码输入 + 保存按钮 + local 缓冲避免每键 IPC
 *
 * R-029 安全: API Key 通过 useConfigStore 走 IPC 通道
 *   渲染层不直接接触 API Key 存储
 */

import React, { useState, useCallback, useEffect } from 'react';
import { Key, Globe, Cpu, Brain, Eye, EyeOff, Check, AlertCircle } from 'lucide-react';
import { useConfigStore } from '../../stores/config.store';
import { useRightPanel } from '../../hooks/useRightPanel';
import styles from '../../styles/SettingsPanel.module.css';
import type { AttitudeLevel } from '../../../shared/types/types-config';

/** 态度档位 UI 标签映射 */
const ATTITUDE_LABELS: ReadonlyArray<{
  value: AttitudeLevel;
  label: string;
  description: string;
}> = [
  { value: 'doubao', label: '温柔', description: '多鼓励,少批评' },
  { value: 'yuesheng', label: '月笙', description: '平衡,有建议有肯定' },
  { value: 'direct', label: '尖锐', description: '直接指出问题' },
];

/** 输入行组件(简化版,无内联样式) */
const ConfigField: React.FC<{
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  secret?: boolean;
  icon?: React.ReactNode;
}> = ({ label, value, onChange, placeholder, secret = false, icon }) => {
  const [show, setShow] = useState(!secret);
  return (
    <div className={styles.field}>
      <label className={styles.label}>
        {icon}
        <span>{label}</span>
      </label>
      <div className={styles.inputRow}>
        <input
          type={show ? 'text' : 'password'}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className={styles.input}
          autoComplete="off"
          spellCheck={false}
        />
        {secret && (
          <button
            type="button"
            onClick={() => setShow(!show)}
            className={styles.eyeBtn}
            aria-label={show ? '隐藏 API Key' : '显示 API Key'}
          >
            {show ? <EyeOff size={12} /> : <Eye size={12} />}
          </button>
        )}
      </div>
    </div>
  );
};

export const SettingsPanel: React.FC = () => {
  // 状态订阅
  const apiKey = useConfigStore((s) => s.apiKey);
  const baseUrl = useConfigStore((s) => s.baseUrl);
  const modelName = useConfigStore((s) => s.modelName);
  const attitudeLevel = useConfigStore((s) => s.attitudeLevel);
  const isLoading = useConfigStore((s) => s.isLoading);
  const isConfigured = useConfigStore((s) => s.isConfigured);

  // 操作订阅
  const setApiKey = useConfigStore((s) => s.setApiKey);
  const setBaseUrl = useConfigStore((s) => s.setBaseUrl);
  const setModelName = useConfigStore((s) => s.setModelName);
  const setAttitudeLevel = useConfigStore((s) => s.setAttitudeLevel);
  const loadConfig = useConfigStore((s) => s.loadConfig);

  // RWR-P0-6: 接入 useRightPanel hook(展示用, 不强制调用)
  const { isOpen } = useRightPanel();

  // 本地编辑缓冲(避免每键触发 IPC 持久化)
  const [localKey, setLocalKey] = useState(apiKey);
  const [localUrl, setLocalUrl] = useState(baseUrl);
  const [localModel, setLocalModel] = useState(modelName);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  // 初始化加载
  useEffect(() => {
    if (isLoading) {
      loadConfig().catch((e) => {
        setSaveStatus('error');
        setErrorMsg(e instanceof Error ? e.message : '加载配置失败');
      });
    }
  }, [isLoading, loadConfig]);

  // 同步 store 状态到 local(外部变更时)
  useEffect(() => setLocalKey(apiKey), [apiKey]);
  useEffect(() => setLocalUrl(baseUrl), [baseUrl]);
  useEffect(() => setLocalModel(modelName), [modelName]);

  // 保存按钮: 仅保存已修改的字段
  const handleSave = useCallback(async () => {
    setSaveStatus('saving');
    setErrorMsg(null);
    try {
      if (localKey !== apiKey) await setApiKey(localKey);
      if (localUrl !== baseUrl) await setBaseUrl(localUrl);
      if (localModel !== modelName) await setModelName(localModel);
      setSaveStatus('success');
      // 2s 后自动隐藏成功状态
      setTimeout(() => setSaveStatus('idle'), 2000);
    } catch (e) {
      setSaveStatus('error');
      setErrorMsg(e instanceof Error ? e.message : '保存失败');
    }
  }, [localKey, localUrl, localModel, apiKey, baseUrl, modelName, setApiKey, setBaseUrl, setModelName]);

  // 态度档位: 立即生效(不需保存按钮)
  const handleAttitudeChange = useCallback(
    async (level: AttitudeLevel) => {
      try {
        await setAttitudeLevel(level);
      } catch (e) {
        setErrorMsg(e instanceof Error ? e.message : '设置态度档位失败');
      }
    },
    [setAttitudeLevel]
  );

  const hasChanges =
    localKey !== apiKey || localUrl !== baseUrl || localModel !== modelName;
  const isSaving = saveStatus === 'saving';

  return (
    <div className={styles.panel}>
      {/* 面板状态提示(用于调试 / 验证 hook 集成) */}
      {isOpen && (
        <div className={styles.statusBar} role="status">
          右栏面板已打开
        </div>
      )}

      {/* API 配置 */}
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>API 配置</h3>
        <div className={styles.fieldList}>
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
        </div>

        <button
          type="button"
          onClick={handleSave}
          disabled={!hasChanges || isSaving}
          className={styles.saveBtn}
          aria-label="保存 API 配置"
        >
          {isSaving ? '保存中...' : '保存配置'}
        </button>

        {/* 保存状态反馈 */}
        {saveStatus === 'success' && (
          <div className={styles.feedbackSuccess} role="status">
            <Check size={12} strokeWidth={2} />
            已保存
          </div>
        )}
        {saveStatus === 'error' && errorMsg && (
          <div className={styles.feedbackError} role="alert">
            <AlertCircle size={12} strokeWidth={2} />
            {errorMsg}
          </div>
        )}
        {isConfigured && saveStatus === 'idle' && !hasChanges && (
          <div className={styles.hint}>配置已保存到本地</div>
        )}
      </section>

      <div className={styles.divider} />

      {/* 态度档位(规格 DoD 要求, 3 态) */}
      <section className={styles.section}>
        <h3 className={styles.sectionTitle}>
          <Brain size={12} strokeWidth={1.6} />
          <span>态度档位</span>
        </h3>
        <p className={styles.sectionDesc}>影响 AI 反馈的鼓励/批评比例</p>
        <div className={styles.attitudeGroup} role="radiogroup" aria-label="态度档位">
          {ATTITUDE_LABELS.map(({ value, label, description }) => (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={attitudeLevel === value}
              aria-label={`${label}: ${description}`}
              onClick={() => handleAttitudeChange(value)}
              className={
                attitudeLevel === value
                  ? `${styles.attitudeBtn} ${styles.attitudeBtnActive}`
                  : styles.attitudeBtn
              }
            >
              <span className={styles.attitudeLabel}>{label}</span>
              <span className={styles.attitudeDesc}>{description}</span>
            </button>
          ))}
        </div>
      </section>
    </div>
  );
};
