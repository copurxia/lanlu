/**
 * 封面相关命令: cover
 *
 * 封面获取规则：
 * - 本地归档：封面通过 cover_asset_id 关联，用 GET /api/assets/{id} 获取图片
 * - 在线源归档：通过 /api/archives/{id}/cover 获取 cover_asset_id
 * - 合集(Tankoubon)：metadata 中 assets.cover 字段提供 cover_asset_id
 */

import { getInt, getString, parseJson } from './json_utils.mjs';
import { printRawJson } from './archive_cmds.mjs';

/**
 * 获取归档或合集的封面 asset_id
 *
 * 用法:
 *   cover <archive-id|tankoubon-id>        获取指定归档/合集的封面 asset_id
 *   cover --archive <id>                    等价于 cover <id>
 *   cover --tankoubon <id>                  获取合集的封面
 *   cover --asset-id <id>                   直接查看 asset_id 对应 URL
 */
export async function handleCover(client, opts, outputMode) {
  const assetIdOpt = opts.options['asset-id'];
  if (assetIdOpt) {
    showAssetUrl(client, assetIdOpt, outputMode);
    return;
  }

  if (opts.args.length < 1) {
    throw new Error('usage: cover <archive-id|tankoubon-id>  or  cover --asset-id <id>');
  }

  const targetId = opts.args[0];

  const body = await client.get(`/api/archives/${encodeURIComponent(targetId)}/cover`);
  const root = parseJson(body, `cover for ${targetId}`);
  const coverAssetId = getInt(root, 'cover_asset_id') ?? 0;

  if (coverAssetId <= 0) {
    if (outputMode === 'text') {
      console.log(`no cover found for ${targetId}`);
    } else {
      printRawJson(body, outputMode);
    }
    return;
  }

  if (outputMode === 'text') {
    const assetUrl = `${client.getHost()}/api/assets/${coverAssetId}`;
    console.log(`cover_asset_id: ${coverAssetId}`);
    console.log(`asset_url:      ${assetUrl}`);
    console.log('');
    console.log('To download:');
    console.log(`  curl -H "Authorization: Bearer $LANLU_TOKEN" "${assetUrl}" -o cover.avif`);
  } else {
    printRawJson(body, outputMode);
  }
}

function showAssetUrl(client, assetId, outputMode) {
  const url = `${client.getHost()}/api/assets/${assetId}`;
  if (outputMode === 'text') {
    console.log(`asset_id: ${assetId}`);
    console.log(`asset_url: ${url}`);
    console.log('');
    console.log('To download:');
    console.log(`  curl -H "Authorization: Bearer $LANLU_TOKEN" "${url}" -o asset.avif`);
  } else {
    console.log(JSON.stringify({ asset_id: parseInt(assetId, 10), asset_url: url }));
  }
}
