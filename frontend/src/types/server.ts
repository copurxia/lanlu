export interface ServerInfo {
  motd: string;
  name: string;
  total_archives: number;
  total_pages_read: number;
  version: string;
  version_desc: string;
  version_name: string;
  db_extensions?: Array<{
    name: string;
    enabled: boolean;
    version?: string;
  }>;
}
