/**
 * 任务相关命令：download-url, upload, metadata-run, task
 */

import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { getString, getInt, parseJson, requireString } from './json_utils.mjs';
import { printRawJson } from './archive_cmds.mjs';
import { waitForTask } from './poll.mjs';

/**
 * 处理 URL 下载
 */
export async function handleDownloadUrl(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: download-url <url> --category-id <id>');
  }
  const url = opts.args[0];
  const categoryId = opts.options['category-id'];
  if (!categoryId) throw new Error('--category-id is required');

  const payload = JSON.stringify({ url, category_id: categoryId });

  const respBody = await client.post('/api/download_url', payload);

  if (outputMode !== 'text') {
    printRawJson(respBody, outputMode);
    return;
  }

  const root = parseJson(respBody, 'download url');
  const job = root.job ?? 0;
  if (job <= 0) {
    console.log(respBody);
    return;
  }
  console.log(`created download task: ${job}`);

  const { wait, interval, timeout } = resolveWait(opts);
  if (wait) {
    const result = await waitForTask(client, job, interval, timeout, outputMode);
    console.log(JSON.stringify(result));
  }
}

/**
 * 处理归档分片上传
 */
export async function handleUpload(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: upload <file> --category-id <id>');
  }
  const filePath = opts.args[0];
  const categoryId = opts.options['category-id'];
  if (!categoryId) throw new Error('--category-id is required');

  const chunkSize = parseInt(opts.options['chunk-size'] ?? '8388608', 10) || 8388608;
  const targetType = opts.options['target-type'] ?? 'archive';
  const overwrite = !!opts.flags['overwrite'];

  const allBytes = readFileSync(filePath);
  const fileSize = allBytes.length;
  const filename = basename(filePath);

  const totalChunks = Math.ceil(fileSize / chunkSize);

  const initPayload = JSON.stringify({
    filename,
    filesize: fileSize,
    chunk_size: chunkSize,
    total_chunks: totalChunks,
    category_id: categoryId,
    target_type: targetType,
    overwrite,
  });

  const initResp = await client.post('/api/assets/upload/init', initPayload);
  const initRoot = parseJson(initResp, 'upload init');
  const taskIdStr = requireString(initRoot, 'taskId');
  const taskId = parseInt(taskIdStr, 10);

  if (outputMode === 'text') {
    console.log(`upload session: ${taskId}, total chunks: ${totalChunks}`);
  }

  let offset = 0;
  for (let i = 0; i < totalChunks; i++) {
    const end = Math.min(offset + chunkSize, fileSize);
    const chunk = allBytes.slice(offset, end);

    const query = {
      taskId: taskIdStr,
      chunkIndex: String(i),
      totalChunks: String(totalChunks),
    };

    const chunkBody = await client.putBytes('/api/assets/upload/chunk', query, chunk);
    if (outputMode === 'text') {
      console.log(`chunk ${i + 1}/${totalChunks} uploaded`);
    }
    if (outputMode === 'json' || outputMode === 'pretty-json') {
      console.log(chunkBody);
    }

    offset = end;
  }

  const { wait, interval, timeout } = resolveWait(opts);
  if (wait) {
    const result = await waitForTask(client, taskId, interval, timeout, outputMode);
    console.log(JSON.stringify(result));
  }
}

/**
 * 处理元数据插件运行
 */
export async function handleMetadataRun(client, opts, outputMode) {
  if (opts.args.length < 2) {
    throw new Error('usage: metadata-run <namespace> <target-id>');
  }
  const namespace = opts.args[0];
  const targetId = opts.args[1];
  const targetType = opts.options['target-type'] ?? 'archive';
  const param = opts.options['param'] ?? '';
  const writeBack = !!opts.flags['write-back'];

  const payload = JSON.stringify({
    target_type: targetType,
    target_id: targetId,
    namespace,
    ...(param ? { param } : {}),
    write_back: writeBack ? '1' : '0',
  });

  const respBody = await client.post('/api/metadata_plugin', payload);

  if (outputMode !== 'text') {
    printRawJson(respBody, outputMode);
    return;
  }

  const root = parseJson(respBody, 'metadata run');
  const job = root.job ?? 0;
  if (job <= 0) {
    console.log(respBody);
    return;
  }
  console.log(`created metadata task: ${job}`);

  const { wait, interval, timeout } = resolveWait(opts);
  if (wait) {
    const result = await waitForTask(client, job, interval, timeout, outputMode);
    console.log(JSON.stringify(result));
  }
}

/**
 * 处理任务详情查询
 */
export async function handleTask(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: task <id>');
  }
  const taskId = parseInt(opts.args[0], 10);
  if (isNaN(taskId)) throw new Error(`invalid task id: ${opts.args[0]}`);

  const body = await client.get(`/api/admin/taskpool/${taskId}`);
  printRawJson(body, outputMode);
}

function resolveWait(opts) {
  const wait = !!opts.flags['wait'];
  const interval = parseInt(opts.options['interval'] ?? '1000', 10) || 1000;
  const timeout = parseInt(opts.options['timeout'] ?? '300000', 10) || 300000;
  return { wait, interval, timeout };
}
