import { apiClient } from '../api';

export type PluginParameterType = 'string' | 'int' | 'bool' | 'array';
type PluginConfigMap = Record<string, unknown>;

export interface PluginSchemaProperty {
  default?: unknown;
  name?: string;
  title?: string;
  type?: string;
}

export interface PluginSchemaDefinition {
  type?: string;
  properties?: Record<string, PluginSchemaProperty> | PluginSchemaProperty[];
  required?: string[];
}

export interface PluginParameter {
  type: PluginParameterType;
  name?: string;
  desc: string;
  default_value?: unknown;
  value?: unknown;
}

export interface PluginSchemaResponse {
  has_schema: boolean;
  parameters?: PluginParameter[] | string;
  parameters_schema?: string | PluginSchemaDefinition;
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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function asBoolean(value: unknown): boolean {
  return value === true || value === 'true';
}

function asString(value: unknown): string | undefined {
  return typeof value === 'string' ? value : undefined;
}

function asSchemaDefinition(value: unknown): PluginSchemaDefinition {
  return isRecord(value) ? (value as PluginSchemaDefinition) : {};
}

function getSchemaProperties(schema: PluginSchemaDefinition): PluginSchemaProperty[] {
  if (Array.isArray(schema.properties)) {
    return schema.properties;
  }

  if (!isRecord(schema.properties)) {
    return [];
  }

  return Object.entries(schema.properties).map(([name, property]) => ({
    name,
    ...(isRecord(property) ? property : {}),
  }));
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

      let actualData: unknown = data;
      if (isRecord(data) && isRecord(data.data)) {
        actualData = data.data;
      }

      if (typeof actualData === 'string') {
        const parsed = JSON.parse(actualData) as unknown;
        if (!isRecord(parsed)) {
          return { has_schema: false, message: 'Invalid schema response' };
        }

        return {
          has_schema: asBoolean(parsed.has_schema),
          parameters:
            typeof parsed.parameters === 'string' || Array.isArray(parsed.parameters)
              ? (parsed.parameters as PluginParameter[] | string)
              : undefined,
          parameters_schema:
            typeof parsed.parameters_schema === 'string'
              ? parsed.parameters_schema
              : asSchemaDefinition(parsed.parameters_schema),
          message: asString(parsed.message),
        };
      }

      if (!isRecord(actualData)) {
        return { has_schema: false, message: 'Invalid schema response' };
      }

      return {
        has_schema: asBoolean(actualData.has_schema),
        parameters:
          typeof actualData.parameters === 'string' || Array.isArray(actualData.parameters)
            ? (actualData.parameters as PluginParameter[] | string)
            : undefined,
        parameters_schema:
          typeof actualData.parameters_schema === 'string'
            ? actualData.parameters_schema
            : asSchemaDefinition(actualData.parameters_schema),
        message: asString(actualData.message),
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

      const schema = this.parseSchema(schemaResponse.parameters_schema);
      const defaults: PluginConfigMap = {};

      getSchemaProperties(schema).forEach((property) => {
        const key = property.name;
        if (!key) return;

        if (property.default !== undefined) {
          defaults[key] = property.default;
          return;
        }

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
            break;
        }
      });

      return {
        has_schema: true,
        defaults: JSON.stringify(defaults)
      };
    } catch (error) {
      console.error('Failed to fetch plugin defaults:', error);
      throw error;
    }
  }

  static async updatePluginConfigWithValidation(
    namespace: string,
    data: { parameters: PluginParameter[] }
  ): Promise<PluginConfigUpdateResponse> {
    try {
      const requestBody = {
        parameters: JSON.stringify(data.parameters)
      };

      const response = await apiClient.put(`/api/admin/plugins/${namespace}/config`, requestBody);
      const responseData = response.data;
      if (typeof responseData === 'string') {
        const parsed = JSON.parse(responseData) as unknown;
        if (!isRecord(parsed)) {
          return { success: false, message: 'Invalid response' };
        }
        return {
          success: parsed.success === 'true',
          message: asString(parsed.message) || ''
        };
      }

      if (!isRecord(responseData)) {
        return { success: false, message: 'Invalid response' };
      }

      return {
        success: Boolean(responseData.success),
        message: asString(responseData.message) || ''
      };
    } catch (error) {
      console.error('Failed to update plugin config:', error);
      throw error;
    }
  }

  static parseSchema(schemaInput: unknown): PluginSchemaDefinition {
    try {
      if (isRecord(schemaInput)) {
        return schemaInput as PluginSchemaDefinition;
      }
      if (typeof schemaInput === 'string') {
        return asSchemaDefinition(JSON.parse(schemaInput));
      }
      return {};
    } catch (error) {
      console.error('Failed to parse schema:', error);
      return {};
    }
  }

  static pluginSupportsSchema(plugin: { has_schema?: unknown }): boolean {
    return Boolean(plugin.has_schema);
  }

  static mergeConfigs(defaults: PluginConfigMap, current: PluginConfigMap): PluginConfigMap {
    return {
      ...defaults,
      ...current
    };
  }

  static isValidSchema(schema: unknown): boolean {
    const parsed = this.parseSchema(schema);
    return (
      parsed.type === 'object' &&
      parsed.properties !== undefined &&
      typeof parsed.properties === 'object'
    );
  }

  static getSchemaFields(schema: unknown): Array<{name: string, title: string, type: string, required: boolean}> {
    const parsed = this.parseSchema(schema);
    if (!this.isValidSchema(parsed)) {
      return [];
    }

    const required = Array.isArray(parsed.required) ? parsed.required : [];
    return getSchemaProperties(parsed)
      .filter((field) => typeof field.name === 'string' && field.name.trim() !== '')
      .map((field) => ({
        name: field.name as string,
        title: field.title || field.name || '',
        type: field.type || 'string',
        required: required.includes(field.name || '')
      }));
  }
}
