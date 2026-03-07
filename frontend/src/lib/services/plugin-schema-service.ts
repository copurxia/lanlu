import { apiClient } from '../api';

export type PluginParameterType = 'string' | 'int' | 'bool' | 'array';

export interface PluginParameter {
  type: PluginParameterType;
  name?: string;
  desc: string;
  default_value?: any;
  value?: any;
}

export interface PluginSchemaResponse {
  has_schema: boolean;
  parameters?: PluginParameter[] | string;
  parameters_schema?: string | any;
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
  static async getPluginSchema(namespace: string): Promise<PluginSchemaResponse> {
    try {
      if (typeof window === 'undefined') {
        console.warn('⚠️ Not in browser environment, returning empty schema');
        return {
          has_schema: false,
          message: 'Not in browser environment'
        };
      }

      const response = await apiClient.get(`/api/admin/plugins/${namespace}/config`);
      const data = response.data;

      let actualData = data;
      if (data && typeof data === 'object' && data.data && typeof data.data === 'object') {
        actualData = data.data;
      }

      if (typeof actualData === 'string') {
        const parsed = JSON.parse(actualData);

        return {
          has_schema: parsed.has_schema === 'true' || parsed.has_schema === true,
          parameters: parsed.parameters,
          message: parsed.message
        };
      }

      return {
        has_schema: actualData.has_schema === 'true' || actualData.has_schema === true,
        parameters: actualData.parameters,
        message: actualData.message
      };
    } catch (error) {
      console.error('Failed to fetch plugin schema:', error);
      throw error;
    }
  }

  static async getPluginDefaults(namespace: string): Promise<PluginDefaultsResponse> {
    try {
      const schemaResponse = await this.getPluginSchema(namespace);

      if (!schemaResponse.has_schema) {
        return {
          has_schema: false,
          defaults: '{}'
        };
      }

      let schema;
      if (typeof schemaResponse.parameters_schema === 'string') {
        schema = JSON.parse(schemaResponse.parameters_schema || '{}');
      } else {
        schema = schemaResponse.parameters_schema || {};
      }
      const defaults: Record<string, any> = {};

      if (schema.properties && Array.isArray(schema.properties)) {
        schema.properties.forEach((property: any) => {
          const key = property.name;
          if (property.default !== undefined) {
            defaults[key] = property.default;
          } else {
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
              case 'array':
                defaults[key] = [];
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

  static async updatePluginConfigWithValidation(namespace: string, data: { parameters: any[] }): Promise<PluginConfigUpdateResponse> {
    try {
      const requestBody = {
        parameters: JSON.stringify(data.parameters)
      };

      const response = await apiClient.put(`/api/admin/plugins/${namespace}/config`, requestBody);
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

  static parseSchema(schemaInput: string | any): any {
    try {
      if (typeof schemaInput === 'object' && schemaInput !== null) {
        return schemaInput;
      }
      if (typeof schemaInput === 'string') {
        return JSON.parse(schemaInput);
      }
      return {};
    } catch (error) {
      console.error('Failed to parse schema:', error);
      return {};
    }
  }

  static pluginSupportsSchema(plugin: any): boolean {
    return plugin.has_schema || false;
  }

  static mergeConfigs(defaults: Record<string, any>, current: Record<string, any>): Record<string, any> {
    return {
      ...defaults,
      ...current
    };
  }

  static isValidSchema(schema: any): boolean {
    return schema &&
           typeof schema === 'object' &&
           schema.type === 'object' &&
           schema.properties &&
           typeof schema.properties === 'object';
  }

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
