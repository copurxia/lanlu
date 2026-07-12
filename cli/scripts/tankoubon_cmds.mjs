/**
 * 合集(Tankoubon)相关命令: tankoubon-list, tankoubon-show
 *
 * API：
 *   GET /api/tankoubons          — 列出所有合集
 *   GET /api/tankoubons/{id}/metadata — 合集详情（含子归档列表）
 */

import { getString, getInt, getArray, parseJson } from './json_utils.mjs';
import { printRawJson, printJsonOrText } from './archive_cmds.mjs';

/**
 * 列出所有合集
 */
export async function handleTankoubonList(client, _opts, outputMode) {
  const body = await client.get('/api/tankoubons');
  printJsonOrText(body, outputMode, printTankoubonList);
}

function printTankoubonList(body) {
  const root = parseJson(body, 'tankoubon list');
  const items = getArray(root, 'result');
  if (!items || items.length === 0) {
    console.log('no tankoubon collections found');
    return;
  }

  console.log('id\ttitle\tarchives\tpages\tcover_asset_id');
  for (const o of items) {
    const tid = getString(o, 'tankoubon_id') ?? '';
    const title = getString(o, 'title') ?? '';
    const count = getInt(o, 'archive_count') ?? 0;
    const pages = getInt(o, 'pagecount') ?? 0;
    const assets = o.assets ?? {};
    const coverId = getInt(assets, 'cover') ?? '';
    console.log(`${tid}\t${title}\t${count}\t${pages}\t${coverId}`);
  }
}

/**
 * 显示合集详情（metadata + 子归档列表）
 */
export async function handleTankoubonShow(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: tankoubon-show <id>');
  }
  const id = opts.args[0];

  const metaBody = await client.get(`/api/tankoubons/${encodeURIComponent(id)}/metadata`);
  printJsonOrText(metaBody, outputMode, (body) => printTankoubonDetail(body, client));
}

function printTankoubonDetail(body, client) {
  const root = parseJson(body, 'tankoubon detail');

  const tid = getString(root, 'tankoubon_id') ?? '';
  const title = getString(root, 'title') ?? '';
  const desc = getString(root, 'description') ?? '';
  const tags = getString(root, 'tags') ?? '';
  const pagecount = getInt(root, 'pagecount') ?? 0;
  const archiveCount = getInt(root, 'archive_count') ?? 0;
  const progress = getInt(root, 'progress') ?? 0;
  const isNew = root.isnew ?? false;
  const isFav = root.isfavorite ?? false;
  const assets = root.assets ?? {};

  console.log(`tankoubon_id:  ${tid}`);
  console.log(`title:         ${title}`);
  console.log(`description:   ${desc}`);
  console.log(`tags:          ${tags}`);
  console.log(`archive_count: ${archiveCount}`);
  console.log(`pagecount:     ${pagecount}`);
  console.log(`progress:      ${progress}%`);
  console.log(`isnew:         ${isNew}`);
  console.log(`isfavorite:    ${isFav}`);

  const coverId = getInt(assets, 'cover');
  if (coverId && coverId > 0) {
    const assetUrl = `${client.getHost()}/api/assets/${coverId}`;
    console.log(`cover_asset_id: ${coverId}`);
    console.log(`cover_url:      ${assetUrl}`);
  }

  // 子归档列表 (children)
  const children = getArray(root, 'children');
  if (children && children.length > 0) {
    console.log('');
    console.log(`archives (${children.length}):`);
    for (const child of children) {
      if (typeof child === 'string') {
        console.log(`  ${child}`);
      } else if (typeof child === 'object' && child !== null) {
        // Plugin source 返回的对象格式
        const entityId = getString(child, 'entity_id') ?? '';
        const childTitle = getString(child, 'title') ?? '';
        console.log(`  ${entityId}  ${childTitle}`);
      }
    }
  }
}
