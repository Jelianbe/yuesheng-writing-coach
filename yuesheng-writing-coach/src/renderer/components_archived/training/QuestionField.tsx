/**
 * QuestionField — 三问输入框子组件
 *
 * 从 BehaviorDerivationTool.tsx 拆出的问题输入字段组件。
 */

import React from 'react';
import { fieldRowStyle, labelStyle, inputStyle } from './BehaviorDerivation.styles';

export interface QuestionFieldProps {
  number: number;
  label: string;
  value: string;
  onChange: (v: string) => void;
}

export const QuestionField: React.FC<QuestionFieldProps> = ({ number, label, value, onChange }) => (
  <div style={fieldRowStyle}>
    <label style={labelStyle}>问题{number}：{label}</label>
    <textarea
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={`输入"${label}"的回答...`}
      rows={2}
      style={inputStyle}
    />
  </div>
);
