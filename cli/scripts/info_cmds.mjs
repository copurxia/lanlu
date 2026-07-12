/**
 * 服务器信息命令: info
 */

import { getString, getInt, getArray } from './json_utils.mjs';

/**
 * 处理服务器信息查询
 */
export async function handleInfo(client, _opts, outputMode) {
  const body = await client.get('/api/info');

  if (outputMode !== 'text') {
    if (outputMode === 'pretty-json') {
      console.log(JSON.stringify(JSON.parse(body), null, 2));
    } else {
      console.log(body);
    }
    return;
  }

  const info = JSON.parse(body);

  console.log(`Server:       ${getString(info, 'name') ?? '(unknown)'}`);
  console.log(`MOTD:         ${getString(info, 'motd') ?? ''}`);
  console.log(`Version:      ${getString(info, 'version_desc') ?? ''}`);
  console.log(`Runtime:      ${getString(info, 'version_name') ?? ''}`);
  console.log(`Archives:     ${getInt(info, 'total_archives') ?? 0}`);
  console.log(`Pages read:   ${getInt(info, 'total_pages_read') ?? 0}`);

  const dbExts = getArray(info, 'db_extensions');
  if (dbExts && dbExts.length > 0) {
    console.log('DB Extensions:');
    for (const ext of dbExts) {
      const name = getString(ext, 'name') ?? '';
      const enabled = ext.enabled ? 'enabled' : 'disabled';
      const ver = getString(ext, 'version') ?? '';
      console.log(`  ${name}: ${enabled} (${ver})`);
    }
  }
}
