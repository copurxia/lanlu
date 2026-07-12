/**
 * 归档相关命令：search, archive-show, category-list
 */

import {
  getString, getInt, getArray, parseJson,
} from './json_utils.mjs';

/**
 * 处理本地归档搜索
 */
export async function handleSearch(client, opts, outputMode) {
  const filter = opts.args.length > 0 ? opts.args[0] : '';
  const params = {};
  params.filter = filter;
  addIfPresent(opts, params, 'category');
  addIfPresent(opts, params, 'page');
  addIfPresent(opts, params, 'page-size', 'pageSize');
  addIfPresent(opts, params, 'sortby');
  addIfPresent(opts, params, 'order');
  addFlagIfPresent(opts, params, 'new-only', 'newonly');
  addFlagIfPresent(opts, params, 'untagged-only', 'untaggedonly');
  addFlagIfPresent(opts, params, 'favorite-only', 'favoriteonly');
  addFlagIfPresent(opts, params, 'group-by-tanks', 'groupby_tanks');

  const body = await client.get('/api/search', params);

  if (outputMode !== 'text') {
    printRawJson(body, outputMode);
    return;
  }

  const root = parseJson(body, 'search result');
  const data = getArray(root, 'data');
  if (data) printSearchItems(data);

  const groups = getArray(root, 'groups');
  if (groups) {
    for (const g of groups) {
      console.log('');
      console.log(`group category_id=${getString(g, 'category_id') ?? ''}`);
      const items = getArray(g, 'data');
      if (items) printSearchItems(items);
    }
  }

  const total = getInt(root, 'recordsTotal') ?? 0;
  console.log(`total: ${total}`);
}

/**
 * 处理归档详情查询
 */
export async function handleArchiveShow(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: archive-show <arcid>');
  }
  const arcid = opts.args[0];
  const params = {};
  if (opts.flags['include-pages']) {
    params.include_pages = 'true';
  }
  const body = await client.get(`/api/archives/${arcid}/metadata`, params);
  printJsonOrText(body, outputMode, printArchiveDetail);
}

/**
 * 处理分类列表查询
 */
export async function handleCategoryList(client, _opts, outputMode) {
  const body = await client.get('/api/categories');

  if (outputMode !== 'text') {
    printRawJson(body, outputMode);
    return;
  }

  const root = parseJson(body, 'category list');
  const arr = getArray(root, 'data');
  if (!arr) {
    console.log(body);
    return;
  }

  console.log('id\tname\tcount');
  for (const o of arr) {
    const id = o.id ?? '';
    const name = getString(o, 'name') ?? '';
    const count = getInt(o, 'archive_count') ?? 0;
    console.log(`${id}\t${name}\t${count}`);
  }
}

function printSearchItems(data) {
  for (const o of data) {
    const itemType = getString(o, 'type') ?? 'archive';
    if (itemType === 'tankoubon') {
      const tid = getString(o, 'tankoubon_id') ?? '';
      const title = getString(o, 'title') ?? '';
      const count = getInt(o, 'archive_count') ?? 0;
      console.log(`[tank] ${tid} ${title} (${count} archives)`);
    } else {
      const arcid = getString(o, 'arcid') ?? '';
      const title = getString(o, 'title') ?? '';
      const pagecount = getInt(o, 'pagecount') ?? 0;
      const tags = getString(o, 'tags') ?? '';
      console.log(`${arcid} | ${title} | ${pagecount}p | ${tags}`);
    }
  }
}

function printArchiveDetail(body) {
  const root = parseJson(body, 'archive detail');
  console.log(`arcid: ${getString(root, 'arcid') ?? ''}`);
  console.log(`title: ${getString(root, 'title') ?? ''}`);
  console.log(`filename: ${getString(root, 'filename') ?? ''}`);
  console.log(`pagecount: ${getInt(root, 'pagecount') ?? 0}`);
  console.log(`archivetype: ${getString(root, 'archivetype') ?? ''}`);
  console.log(`tags: ${getString(root, 'tags') ?? ''}`);
  console.log(`description: ${getString(root, 'description') ?? ''}`);
  const pages = getArray(root, 'pages');
  if (pages) console.log(`pages: ${pages.length}`);
}

function addIfPresent(opts, params, optName, paramName) {
  const v = opts.options[optName];
  if (v !== undefined && v !== '') {
    params[paramName ?? optName] = v;
  }
}

function addFlagIfPresent(opts, params, optName, paramName) {
  if (opts.flags[optName]) {
    params[paramName] = 'true';
  }
}

export function printRawJson(body, outputMode) {
  if (outputMode === 'pretty-json') {
    console.log(JSON.stringify(JSON.parse(body), null, 2));
  } else {
    console.log(body);
  }
}

export function printJsonOrText(body, outputMode, textPrinter) {
  if (outputMode === 'text') {
    textPrinter(body);
  } else if (outputMode === 'pretty-json') {
    console.log(JSON.stringify(JSON.parse(body), null, 2));
  } else {
    console.log(body);
  }
}
