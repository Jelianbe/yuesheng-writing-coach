/**
 * IPC 入参校验中间件（R-028 防御性编码）
 *
 * 提供通用 payload 校验函数，用于 IPC handler 边界层防御。
 * 内部业务逻辑不依赖此校验（由 TypeScript 类型保证）。
 *
 * 使用方法：
 *   const validation = validatePayload(args, { required: ['id', 'message'], types: { id: 'string', message: 'string' } });
 *   if (!validation.valid) return apiError(validation.error!);
 */

export interface ValidationError {
  code: 'INVALID_PAYLOAD' | 'MISSING_FIELD' | 'INVALID_TYPE' | 'OUT_OF_RANGE';
  message: string;
  field?: string;
}

export interface PayloadSchema {
  /** 必填字段名列表 */
  required?: string[];
  /** 字段类型映射：string | number | boolean | object | array */
  types?: Record<string, 'string' | 'number' | 'boolean' | 'object' | 'array'>;
  /** 字段范围检查：{ fieldName: { min, max } }（仅对 number 类型生效） */
  ranges?: Record<string, { min?: number; max?: number }>;
}

export type ValidationResult<T = unknown> =
  | { valid: true; data: T }
  | { valid: false; error: ValidationError; data: null };

/**
 * 校验 IPC handler 入参
 */
export function validatePayload<T extends Record<string, unknown> = Record<string, unknown>>(
  data: unknown,
  schema: PayloadSchema,
): ValidationResult<T> {
  // 1. 基础类型检查：必须是对象且非 null
  if (data === null || data === undefined || typeof data !== 'object' || Array.isArray(data)) {
    return {
      valid: false,
      error: { code: 'INVALID_PAYLOAD', message: '入参必须是对象类型' },
      data: null,
    };
  }

  const obj = data as Record<string, unknown>;

  // 2. 必填字段检查
  if (schema.required) {
    for (const field of schema.required) {
      if (obj[field] === undefined || obj[field] === null) {
        return {
          valid: false,
          error: { code: 'MISSING_FIELD', message: `缺少必填字段: ${field}`, field },
          data: null,
        };
      }
    }
  }

  // 3. 类型检查
  if (schema.types) {
    for (const [field, expectedType] of Object.entries(schema.types)) {
      const value = obj[field];
      if (value === undefined) continue; // 可选字段跳过

      const actualType = Array.isArray(value) ? 'array' : typeof value;
      if (actualType !== expectedType) {
        return {
          valid: false,
          error: {
            code: 'INVALID_TYPE',
            message: `字段 ${field} 类型错误：期望 ${expectedType}，实际 ${actualType}`,
            field,
          },
          data: null,
        };
      }
    }
  }

  // 4. 范围检查（仅对 number 类型）
  if (schema.ranges) {
    for (const [field, range] of Object.entries(schema.ranges)) {
      const value = obj[field];
      if (typeof value !== 'number') continue;

      if (range.min !== undefined && value < range.min) {
        return {
          valid: false,
          error: {
            code: 'OUT_OF_RANGE',
            message: `字段 ${field} 值 ${value} 小于最小值 ${range.min}`,
            field,
          },
          data: null,
        };
      }
      if (range.max !== undefined && value > range.max) {
        return {
          valid: false,
          error: {
            code: 'OUT_OF_RANGE',
            message: `字段 ${field} 值 ${value} 大于最大值 ${range.max}`,
            field,
          },
          data: null,
        };
      }
    }
  }

  return { valid: true, data: obj as T };
}

/**
 * 快捷校验：字符串非空检查
 */
export function requireString(value: unknown, fieldName: string): ValidationError | null {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return {
      code: 'INVALID_TYPE',
      message: `${fieldName} 必须是非空字符串`,
      field: fieldName,
    };
  }
  return null;
}
