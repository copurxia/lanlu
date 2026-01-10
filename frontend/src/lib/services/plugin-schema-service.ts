import { apiClient } from '../api';

// 插件参数定义 - 对应后端 PluginParameter
export interface PluginParameter {
  type: 'string' | 'int' | 'bool';
  name?: string;
  desc: string;
  default_value?: string;
  value?: any;  // 用户配置的值
}

export interface PluginSchemaResponse {
  has_schema: boolean;
  parameters?: PluginParameter[];  // PluginParameter数组
  parameters_schema?: string | any;  // 向后兼容
  message?: string;
}

export interface PluginValidationResponse {
  valid: boolean;
  error?: string;
  message?: string;
}

export interface PluginDefaultsResponse {
  has_schema: boolean;
  defaults: string;
}

export interface PluginConfigUpdateResponse {
  success: boolean;
  message: string;
}

export class PluginSchemaService {
  /**
   * 获取插件的配置Schema
   */
  static async getPluginSchema(namespace: string): Promise<PluginSchemaResponse> {
    try {


      // 检查是否在浏览器环境中
      if (typeof window === 'undefined') {
        console.warn('⚠️ Not in browser environment, returning empty schema');
        return {
          has_schema: false,
          message: 'Not in browser environment'
        };
      }

      const response = await apiClient.get(`/api/plugins/${namespace}/config`);


      // 解析响应数据
      const data = response.data;


      // 处理新的API响应格式：{success: true, data: {has_schema: true, parameters: [...], message: ...}}
      let actualData = data;
      if (data && typeof data === 'object' && data.data && typeof data.data === 'object') {
        actualData = data.data;

      }

      if (typeof actualData === 'string') {
        const parsed = JSON.parse(actualData);

        return {
          has_schema: parsed.has_schema === 'true' || parsed.has_schema === true,
          parameters: parsed.parameters,  // parameters现在应该是数组
          message: parsed.message
        };
      }


      return {
        has_schema: actualData.has_schema === 'true' || actualData.has_schema === true,
        parameters: actualData.parameters,  // parameters现在应该是数组
        message: actualData.message
      };
    } catch (error) {
      console.error('Failed to fetch plugin schema:', error);
      throw error;
    }
  }

  /**
   * 验证插件配置
   */
  static async validatePluginConfig(namespace: string, config: Record<string, any>): Promise<PluginValidationResponse> {
    try {
      const response = await apiClient.post(`/api/plugins/${namespace}/validate`, config);

      const data = response.data;
      if (typeof data === 'string') {
        const parsed = JSON.parse(data);
        return {
          valid: parsed.valid === 'true',
          error: parsed.error,
          message: parsed.message
        };
      }

      return {
        valid: data.valid,
        error: data.error,
        message: data.message
      };
    } catch (error) {
      console.error('Failed to validate plugin config:', error);
      throw error;
    }
  }

  /**
   * 获取插件默认配置 - 从schema中计算默认值
   */
  static async getPluginDefaults(namespace: string): Promise<PluginDefaultsResponse> {
    try {
      // 首先获取schema
      const schemaResponse = await this.getPluginSchema(namespace);

      if (!schemaResponse.has_schema) {
        return {
          has_schema: false,
          defaults: '{}'
        };
      }

      // 从schema中提取默认值
      let schema;
      if (typeof schemaResponse.parameters_schema === 'string') {
        schema = JSON.parse(schemaResponse.parameters_schema || '{}');
      } else {
        schema = schemaResponse.parameters_schema || {};
      }
      const defaults: Record<string, any> = {};

      if (schema.properties && Array.isArray(schema.properties)) {
        // 处理数组格式的properties
        schema.properties.forEach((property: any) => {
          const key = property.name;
          if (property.default !== undefined) {
            defaults[key] = property.default;
          } else {
            // 根据type设置默认值
            switch (property.type) {
              case 'string':
                defaults[key] = '';
                break;
              case 'bool':
              case 'boolean':
                defaults[key] = false;
                break;
              case 'number':
                defaults[key] = 0;
                break;
              default:
                defaults[key] = null;
            }
          }
        });
      }

      return {
        has_schema: true,
        defaults: JSON.stringify(defaults)
      };
    } catch (error) {
      console.error('Failed to fetch plugin defaults:', error);
      throw error;
    }
  }

  /**
   * 更新插件配置（带验证）- 发送完整的parameters数组
   */
  static async updatePluginConfigWithValidation(namespace: string, data: { parameters: any[] }): Promise<PluginConfigUpdateResponse> {
    try {
      // 构建请求体：{ "parameters": "[...]" }
      const requestBody = {
        parameters: JSON.stringify(data.parameters)
      };

      const response = await apiClient.put(`/api/plugins/${namespace}/config`, requestBody);

      const responseData = response.data;
      if (typeof responseData === 'string') {
        const parsed = JSON.parse(responseData);
        return {
          success: parsed.success === 'true',
          message: parsed.message
        };
      }

      return {
        success: responseData.success,
        message: responseData.message
      };
    } catch (error) {
      console.error('Failed to update plugin config:', error);
      throw error;
    }
  }

  /**
   * 解析Schema字符串为对象
   */
  static parseSchema(schemaInput: string | any): any {
    try {
      // 如果输入已经是对象，直接返回
      if (typeof schemaInput === 'object' && schemaInput !== null) {
        return schemaInput;
      }
      // 如果是字符串，解析为JSON
      if (typeof schemaInput === 'string') {
        return JSON.parse(schemaInput);
      }
      // 其他情况返回空对象
      return {};
    } catch (error) {
      console.error('Failed to parse schema:', error);
      return {};
    }
  }

  /**
   * 检查插件是否支持Schema
   */
  static pluginSupportsSchema(plugin: any): boolean {
    return plugin.has_schema || false;
  }

  /**
   * 合并默认配置和现有配置
   */
  static mergeConfigs(defaults: Record<string, any>, current: Record<string, any>): Record<string, any> {
    return {
      ...defaults,
      ...current
    };
  }

  /**
   * 验证Schema格式
   */
  static isValidSchema(schema: any): boolean {
    return schema &&
           typeof schema === 'object' &&
           schema.type === 'object' &&
           schema.properties &&
           typeof schema.properties === 'object';
  }

  /**
   * 获取Schema中的字段信息
   */
  static getSchemaFields(schema: any): Array<{name: string, title: string, type: string, required: boolean}> {
    if (!this.isValidSchema(schema)) {
      return [];
    }

    const required = schema.required || [];
    return Object.entries(schema.properties).map(([name, field]: [string, any]) => ({
      name,
      title: field.title || name,
      type: field.type || 'string',
      required: required.includes(name)
    }));
  }
}
