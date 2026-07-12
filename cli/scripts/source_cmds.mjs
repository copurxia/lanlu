/**
 * Source 插件相关命令：source-list, source-home, source-search, source-filters, source-download
 */

import { getString, getBool, getObject, getArray, parseJson } from './json_utils.mjs';
import { printRawJson, printJsonOrText } from './archive_cmds.mjs';
import { waitForTask } from './poll.mjs';

/**
 * 处理 Source 插件列表
 */
export async function handleSourceList(client, _opts, outputMode) {
  const body = await client.get('/api/admin/source-plugins');
  printJsonOrText(body, outputMode, printSourceList);
}

/**
 * 处理 Source 首页
 */
export async function handleSourceHome(client, opts, outputMode) {
  await handleSourceAction(client, opts, outputMode, 'source_home');
}

/**
 * 处理 Source 搜索
 */
export async function handleSourceSearch(client, opts, outputMode) {
  await handleSourceAction(client, opts, outputMode, 'source_search');
}

/**
 * 处理 Source 筛选器
 */
export async function handleSourceFilters(client, opts, outputMode) {
  await handleSourceAction(client, opts, outputMode, 'source_filters');
}

/**
 * 处理 Source 下载
 */
export async function handleSourceDownload(client, opts, outputMode) {
  if (opts.args.length < 2) {
    throw new Error('usage: source-download <namespace> <remote-id> --category-id <id>');
  }
  const namespace = opts.args[0];
  const remoteId = opts.args[1];
  const categoryId = opts.options['category-id'];
  if (!categoryId) throw new Error('--category-id is required');
  const kind = opts.options['kind'] ?? 'archive';

  const body = JSON.stringify({
    remote_id: remoteId,
    category_id: categoryId,
    kind,
  });

  const respBody = await client.post(`/api/admin/source-plugins/${namespace}/download`, body);

  if (outputMode !== 'text') {
    printRawJson(respBody, outputMode);
    return;
  }

  const root = parseJson(respBody, 'source download');
  const taskId = root.task_id ?? 0;
  if (taskId <= 0) {
    console.log(respBody);
    return;
  }
  console.log(`created source download task: ${taskId}`);

  const { wait, interval, timeout } = resolveWait(opts);
  if (wait) {
    const result = await waitForTask(client, taskId, interval, timeout, outputMode);
    console.log(JSON.stringify(result));
  }
}

async function handleSourceAction(client, opts, outputMode, action) {
  if (opts.args.length < 1) {
    throw new Error(`usage: ${action} <namespace> [query]`);
  }
  const namespace = opts.args[0];

  const payload = {};

  if (action === 'source_search') {
    const query = opts.args.length > 1 ? opts.args[1] : '';
    payload.query = query;

    const page = parseInt(opts.options['page'] ?? '1', 10);
    payload.page = isNaN(page) ? 1 : page;

    const filters = opts.options['filters'];
    if (filters) {
      try {
        payload.filters = JSON.parse(filters);
      } catch (e) {
        throw new Error(`invalid --filters JSON: ${e.message}`);
      }
    }
  }

  const body = await client.post(
    `/api/admin/source-plugins/${namespace}/action/${action}`,
    JSON.stringify(payload),
  );
  printJsonOrText(body, outputMode, printSourceItems);
}

function printSourceList(body) {
  const arr = JSON.parse(body);
  console.log('namespace\tname\tenabled');
  for (const o of arr) {
    const ns = getString(o, 'namespace') ?? '';
    const name = getString(o, 'name') ?? '';
    const enabled = getBool(o, 'enabled') ?? false;
    console.log(`${ns}\t${name}\t${enabled}`);
  }
}

function printSourceItems(body) {
  const root = parseJson(body, 'source action');
  const data = getObject(root, 'data');
  if (!data) {
    console.log(body);
    return;
  }
  const items = getArray(data, 'items');
  if (!items) {
    console.log(body);
    return;
  }
  for (const o of items) {
    const title = getString(o, 'title') ?? '';
    const remoteId = getString(o, 'remote_id') ?? '';
    const kind = getString(o, 'kind') ?? 'archive';
    console.log(`[${kind}] ${remoteId} ${title}`);
  }
}

function resolveWait(opts) {
  const wait = !!opts.flags['wait'];
  const interval = parseInt(opts.options['interval'] ?? '1000', 10) || 1000;
  const timeout = parseInt(opts.options['timeout'] ?? '300000', 10) || 300000;
  return { wait, interval, timeout };
}
