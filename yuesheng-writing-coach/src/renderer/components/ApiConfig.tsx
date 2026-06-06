// API 配置页面组件
// 负责：配置表单、输入验证、状态展示、连接测试
// 依赖：React, Tailwind CSS, config.store

import React, { useEffect, useState, useCallback } from 'react';
import { useConfigStore } from '../stores/config.store';
import { SpinnerIcon, CheckIcon, XIcon, EyeIcon, EyeOffIcon } from './common/Icons';
/**
 * API 配置页面组件
 * 提供 API Key、Base URL、Model Name、Temperature 的配置界面
 */
export const ApiConfig: React.FC = () => {
  const {
    apiKey,
    baseUrl,
    modelName,
    temperature,
    isConfigured,
    isLoading,
    testStatus,
    testError,
    testResponseTime,
    validation,
    setApiKey,
    setBaseUrl,
    setModelName,
    setTemperature,
    testConnection,
    loadConfig,
  } = useConfigStore();

  // 本地表单状态（避免频繁 IPC 调用）
  const [localApiKey, setLocalApiKey] = useState(apiKey);
  const [localBaseUrl, setLocalBaseUrl] = useState(baseUrl);
  const [localModelName, setLocalModelName] = useState(modelName);
  const [localTemperature, setLocalTemperature] = useState(temperature);
  const [showApiKey, setShowApiKey] = useState(false);
  const [isSaving, setIsSaving] = useState(false);

  // 组件挂载时加载配置
  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  // 同步 store 状态到本地状态
  useEffect(() => {
    setLocalApiKey(apiKey);
  }, [apiKey]);

  useEffect(() => {
    setLocalBaseUrl(baseUrl);
  }, [baseUrl]);

  useEffect(() => {
    setLocalModelName(modelName);
  }, [modelName]);

  useEffect(() => {
    setLocalTemperature(temperature);
  }, [temperature]);

  /** 保存所有配置到主进程 */
  const handleSave = useCallback(async () => {
    setIsSaving(true);
    try {
      await Promise.all([
        setApiKey(localApiKey),
        setBaseUrl(localBaseUrl),
        setModelName(localModelName),
        setTemperature(localTemperature),
      ]);
    } finally {
      setIsSaving(false);
    }
  }, [localApiKey, localBaseUrl, localModelName, localTemperature, setApiKey, setBaseUrl, setModelName, setTemperature]);

  /** 测试 API 连接 */
  const handleTestConnection = useCallback(async () => {
    await testConnection();
  }, [testConnection]);

  /** 渲染测试状态指示器 */
  const renderTestStatus = (): React.ReactNode => {
    switch (testStatus) {
      case 'testing':
        return (
          <div className="flex items-center gap-2 text-yellow-600">
            <SpinnerIcon className="w-4 h-4" />
            <span>正在测试连接...</span>
          </div>
        );
      case 'success':
        return (
          <div className="flex items-center gap-2 text-green-600">
            <CheckIcon className="w-4 h-4" />
            <span>连接成功</span>
            {testResponseTime && (
              <span className="text-xs text-gray-500">({testResponseTime}ms)</span>
            )}
          </div>
        );
      case 'error':
        return (
          <div className="flex flex-col gap-1">
            <div className="flex items-center gap-2 text-red-600">
              <XIcon className="w-4 h-4" />
              <span>连接失败</span>
            </div>
            {testError && (
              <p className="text-sm text-red-500 ml-6">{testError}</p>
            )}
          </div>
        );
      default:
        return null;
    }
  };

  /** 渲染校验错误列表 */
  const renderValidationErrors = (): React.ReactNode => {
    if (validation.isValid || validation.errors.length === 0) {
      return null;
    }
    return (
      <div className="mt-4 p-3 bg-red-50 border border-red-200 rounded-lg">
        <ul className="list-disc list-inside text-sm text-red-700">
          {validation.errors.map((error, index) => (
            <li key={index}>{error}</li>
          ))}
        </ul>
      </div>
    );
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center p-8">
        <SpinnerIcon className="w-6 h-6 text-gray-500 animate-spin" />
        <span className="ml-2 text-gray-500">加载配置中...</span>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto p-6">
      <div className="mb-6">
        <h2 className="text-2xl font-bold text-gray-900">API 配置</h2>
        <p className="text-sm text-gray-500 mt-1">
          配置您的 AI 服务连接信息
        </p>
        <div className="mt-2">
          {isConfigured ? (
            <span className="inline-flex items-center gap-1 text-xs font-medium px-2 py-1 bg-green-100 text-green-800 rounded-full">
              <CheckIcon className="w-3 h-3" />
              已配置
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 text-xs font-medium px-2 py-1 bg-yellow-100 text-yellow-800 rounded-full">
              未配置
            </span>
          )}
        </div>
      </div>

      <form onSubmit={(e) => { e.preventDefault(); void handleSave(); }} className="space-y-6">
        {/* API Key */}
        <FormField label="API Key" required>
          <div className="relative">
            <input
              type={showApiKey ? 'text' : 'password'}
              value={localApiKey}
              onChange={(e) => setLocalApiKey(e.target.value)}
              placeholder="sk-..."
              className="w-full px-3 py-2 pr-10 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
            />
            <button
              type="button"
              onClick={() => setShowApiKey(!showApiKey)}
              className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-gray-500 hover:text-gray-700"
              title={showApiKey ? '隐藏' : '显示'}
            >
              {showApiKey ? <EyeOffIcon className="w-4 h-4" /> : <EyeIcon className="w-4 h-4" />}
            </button>
          </div>
        </FormField>

        {/* Base URL */}
        <FormField label="Base URL" required>
          <input
            type="url"
            value={localBaseUrl}
            onChange={(e) => setLocalBaseUrl(e.target.value)}
            placeholder="https://api.openai.com/v1"
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
          />
        </FormField>

        {/* Model Name */}
        <FormField label="Model Name" required>
          <input
            type="text"
            value={localModelName}
            onChange={(e) => setLocalModelName(e.target.value)}
            placeholder="gpt-4"
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none transition"
          />
        </FormField>

        {/* Temperature */}
        <FormField label="Temperature" required>
          <div className="flex items-center gap-4">
            <input
              type="range"
              min={0}
              max={2}
              step={0.1}
              value={localTemperature}
              onChange={(e) => setLocalTemperature(parseFloat(e.target.value))}
              className="flex-1"
            />
            <span className="text-sm font-mono w-12 text-right">{localTemperature.toFixed(1)}</span>
          </div>
        </FormField>

        {/* 校验错误 */}
        {renderValidationErrors()}

        {/* 操作按钮 */}
        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={isSaving || !validation.isValid}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition"
          >
            {isSaving ? '保存中...' : '保存配置'}
          </button>
          <button
            type="button"
            onClick={handleTestConnection}
            disabled={testStatus === 'testing' || !localApiKey}
            className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition"
          >
            {testStatus === 'testing' ? '测试中...' : '测试连接'}
          </button>
        </div>

        {/* 连接测试结果 */}
        <div className="pt-2">
          {renderTestStatus()}
        </div>
      </form>
    </div>
  );
};

/** 表单字段包装组件 */
interface FormFieldProps {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}

const FormField: React.FC<FormFieldProps> = ({ label, required, children }) => (
  <div>
    <label className="block text-sm font-medium text-gray-700 mb-1">
      {label}
      {required && <span className="text-red-500 ml-1">*</span>}
    </label>
    {children}
  </div>
);
