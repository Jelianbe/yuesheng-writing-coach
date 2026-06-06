import React, { useState } from 'react';
import {
  Settings,
  Key,
  Globe,
  Type,
  Thermometer,
  Eye,
  EyeOff,
  CheckCircle,
  AlertCircle,
  Loader2,
  ArrowLeft,
  Brain,
} from 'lucide-react';
import { Card } from '../common/Card';
import { Button } from '../common/Button';
import { ApiConfig, ConnectionTestResult } from '../../shared/types';
import StudentContextSection from './StudentContextSection';

interface ConfigPageProps {
  config: ApiConfig;
  onSave: (config: ApiConfig) => void;
  onBack: () => void;
  onTestConnection: (apiKey: string, baseUrl: string) => Promise<ConnectionTestResult>;
}

export const ConfigPage: React.FC<ConfigPageProps> = ({
  config,
  onSave,
  onBack,
  onTestConnection,
}) => {
  const [formData, setFormData] = useState<ApiConfig>({
    apiKey: config.apiKey,
    baseUrl: config.baseUrl,
    modelName: config.modelName,
    temperature: config.temperature,
    attitudeLevel: config.attitudeLevel,
    maxTokens: config.maxTokens,
  });

  const [showApiKey, setShowApiKey] = useState(false);
  const [isTesting, setIsTesting] = useState(false);
  const [testResult, setTestResult] = useState<ConnectionTestResult | null>(null);
  const [errors, setErrors] = useState<string[]>([]);

  const handleTest = async () => {
    setIsTesting(true);
    setTestResult(null);
    setErrors([]);
    try {
      const result = await onTestConnection(formData.apiKey, formData.baseUrl);
      setTestResult(result);
      if (!result.success) {
        setErrors([result.error || '连接测试失败']);
      }
    } catch (error) {
      setTestResult({ success: false, error: '连接异常，请检查网络' });
      setErrors(['连接异常，请检查网络']);
    } finally {
      setIsTesting(false);
    }
  };

  const handleSave = () => {
    const newErrors: string[] = [];
    if (!formData.apiKey.trim()) newErrors.push('API Key 不能为空');
    if (!formData.baseUrl.trim()) newErrors.push('Base URL 不能为空');
    if (!formData.modelName.trim()) newErrors.push('模型名称不能为空');
    if (formData.temperature < 0 || formData.temperature > 2)
      newErrors.push('Temperature 必须在 0-2 之间');

    if (newErrors.length > 0) {
      setErrors(newErrors);
      return;
    }

    onSave(formData);
    onBack();
  };

  const updateField = <K extends keyof ApiConfig>(
    key: K,
    value: ApiConfig[K]
  ) => {
    setFormData((prev) => ({ ...prev, [key]: value }));
    setErrors([]);
  };

  return (
    <div className="flex-1 bg-bg-primary overflow-y-auto">
      <div className="max-w-2xl mx-auto p-6">
        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <Button variant="ghost" size="sm" onClick={onBack} leftIcon={<ArrowLeft className="w-4 h-4" />}>
            返回
          </Button>
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-bg-tertiary flex items-center justify-center">
              <Settings className="w-5 h-5 text-text-secondary" />
            </div>
            <h2 className="text-h2 font-semibold text-text-primary">API 配置</h2>
          </div>
        </div>

        {/* Error messages */}
        {errors.length > 0 && (
          <Card className="p-4 mb-6 border border-accent-danger/20 bg-red-50">
            <div className="flex items-start gap-2">
              <AlertCircle className="w-5 h-5 text-accent-danger flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-small font-medium text-accent-danger">
                  请修正以下问题
                </p>
                <ul className="text-tiny text-accent-danger/80 mt-1 space-y-0.5">
                  {errors.map((err, i) => (
                    <li key={i}>- {err}</li>
                  ))}
                </ul>
              </div>
            </div>
          </Card>
        )}

        {/* Test result */}
        {testResult && (
          <Card
            className={`p-4 mb-6 ${
              testResult.success
                ? 'border border-accent-secondary/20 bg-emerald-50'
                : 'border border-accent-danger/20 bg-red-50'
            }`}
          >
            <div className="flex items-center gap-2">
              {testResult.success ? (
                <CheckCircle className="w-5 h-5 text-accent-secondary" />
              ) : (
                <AlertCircle className="w-5 h-5 text-accent-danger" />
              )}
              <p
                className={`text-small font-medium ${
                  testResult.success ? 'text-accent-secondary' : 'text-accent-danger'
                }`}
              >
                {testResult.success
                  ? `连接成功${testResult.responseTime ? ` (响应时间: ${testResult.responseTime}ms)` : ''}`
                  : testResult.error || '连接失败'}
              </p>
            </div>
          </Card>
        )}

        {/* Form */}
        <Card className="p-6 space-y-5">
          {/* API Key */}
          <div>
            <label
              htmlFor="apiKey"
              className="flex items-center gap-2 text-small font-medium text-text-primary mb-2"
            >
              <Key className="w-4 h-4 text-text-muted" />
              API Key
            </label>
            <div className="relative">
              <input
                id="apiKey"
                type={showApiKey ? 'text' : 'password'}
                value={formData.apiKey}
                onChange={(e) => updateField('apiKey', e.target.value)}
                placeholder="sk-..."
                className="w-full py-2.5 px-4 pr-10 text-body bg-bg-tertiary border border-border rounded-md
                  placeholder:text-text-muted
                  focus:outline-none focus:ring-2 focus:ring-accent-primary/50 focus:border-accent-primary
                  transition-all duration-fast"
                aria-describedby="apiKey-help"
              />
              <button
                type="button"
                onClick={() => setShowApiKey(!showApiKey)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-text-muted hover:text-text-secondary transition-colors duration-fast"
                aria-label={showApiKey ? 'Hide API key' : 'Show API key'}
              >
                {showApiKey ? (
                  <EyeOff className="w-4 h-4" />
                ) : (
                  <Eye className="w-4 h-4" />
                )}
              </button>
            </div>
            <p id="apiKey-help" className="text-tiny text-text-muted mt-1.5">
              你的 OpenAI 兼容 API 密钥，将安全存储在本地
            </p>
          </div>

          {/* Base URL */}
          <div>
            <label
              htmlFor="baseUrl"
              className="flex items-center gap-2 text-small font-medium text-text-primary mb-2"
            >
              <Globe className="w-4 h-4 text-text-muted" />
              Base URL
            </label>
            <input
              id="baseUrl"
              type="url"
              value={formData.baseUrl}
              onChange={(e) => updateField('baseUrl', e.target.value)}
              placeholder="https://api.openai.com/v1"
              className="w-full py-2.5 px-4 text-body bg-bg-tertiary border border-border rounded-md
                placeholder:text-text-muted
                focus:outline-none focus:ring-2 focus:ring-accent-primary/50 focus:border-accent-primary
                transition-all duration-fast"
            />
          </div>

          {/* Model Name */}
          <div>
            <label
              htmlFor="modelName"
              className="flex items-center gap-2 text-small font-medium text-text-primary mb-2"
            >
              <Type className="w-4 h-4 text-text-muted" />
              模型名称
            </label>
            <input
              id="modelName"
              type="text"
              value={formData.modelName}
              onChange={(e) => updateField('modelName', e.target.value)}
              placeholder="gpt-4"
              className="w-full py-2.5 px-4 text-body bg-bg-tertiary border border-border rounded-md
                placeholder:text-text-muted
                focus:outline-none focus:ring-2 focus:ring-accent-primary/50 focus:border-accent-primary
                transition-all duration-fast"
            />
          </div>

          {/* Temperature */}
          <div>
            <label
              htmlFor="temperature"
              className="flex items-center gap-2 text-small font-medium text-text-primary mb-2"
            >
              <Thermometer className="w-4 h-4 text-text-muted" />
              Temperature: {formData.temperature.toFixed(1)}
            </label>
            <input
              id="temperature"
              type="range"
              min="0"
              max="2"
              step="0.1"
              value={formData.temperature}
              onChange={(e) => updateField('temperature', parseFloat(e.target.value))}
              className="w-full h-2 bg-bg-tertiary rounded-full appearance-none cursor-pointer
                accent-accent-primary"
            />
            <div className="flex justify-between text-tiny text-text-muted mt-1">
              <span>精确 (0)</span>
              <span>创意 (2)</span>
            </div>
          </div>

          {/* Attitude Level */}
          <div>
            <label className="text-small font-medium text-text-primary mb-2 block">
              态度模式
            </label>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={() => updateField('attitudeLevel', 'doubao')}
                className={[
                  'flex-1 py-2.5 px-4 rounded-md text-small font-medium transition-all duration-fast',
                  formData.attitudeLevel === 'doubao'
                    ? 'bg-accent-primary-light text-accent-primary border border-accent-primary/30'
                    : 'bg-bg-tertiary text-text-secondary border border-border hover:bg-bg-hover',
                ].join(' ')}
              >
                温和
              </button>
              <button
                type="button"
                onClick={() => updateField('attitudeLevel', 'yuesheng')}
                className={[
                  'flex-1 py-2.5 px-4 rounded-md text-small font-medium transition-all duration-fast',
                  formData.attitudeLevel === 'yuesheng'
                    ? 'bg-accent-primary-light text-accent-primary border border-accent-primary/30'
                    : 'bg-bg-tertiary text-text-secondary border border-border hover:bg-bg-hover',
                ].join(' ')}
              >
                严格
              </button>
            </div>
          </div>

          {/* Student Context */}
          <div className="pt-4 border-t border-border">
            <label className="flex items-center gap-2 text-small font-medium text-text-primary mb-3">
              <Brain className="w-4 h-4 text-text-muted" />
              学生模型状态
            </label>

            <StudentContextSection />
          </div>
        </Card>

        {/* Actions */}
        <div className="flex gap-3 mt-6">
          <Button
            variant="secondary"
            onClick={handleTest}
            isLoading={isTesting}
            leftIcon={isTesting ? <Loader2 className="w-4 h-4 animate-spin" /> : undefined}
            fullWidth
          >
            {isTesting ? '测试中...' : '测试连接'}
          </Button>
          <Button variant="primary" onClick={handleSave} fullWidth>
            保存配置
          </Button>
        </div>
      </div>
    </div>
  );
};

// Usage example:
// <ConfigPage
//   config={currentConfig}
//   onSave={handleSaveConfig}
//   onBack={() => setShowConfig(false)}
//   onTestConnection={testConnection}
// />
