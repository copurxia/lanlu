#!/usr/bin/env node

/**
 * Lanlu 命令行客户端入口 (Node.js ESM)
 *
 * 用法: lanlu-cli [options] <command> [args]
 *
 * 环境变量:
 *   LANLU_TOKEN  必填。Bearer Token。
 *   LANLU_HOST   服务端地址，默认 http://localhost:8082
 */

import { LanluApiClient } from './api_client.mjs';
import { handleSearch, handleArchiveShow, handleCategoryList } from './archive_cmds.mjs';
import {
  handleSourceList, handleSourceHome, handleSourceSearch,
  handleSourceFilters, handleSourceDownload,
} from './source_cmds.mjs';
import { handleInfo } from './info_cmds.mjs';
import {
  handleDownloadUrl, handleUpload, handleMetadataRun, handleTask,
} from './task_cmds.mjs';
import { handleCover } from './cover_cmds.mjs';
import { handleTankoubonList, handleTankoubonShow } from './tankoubon_cmds.mjs';
import { handleUpdateMetadata } from './update_metadata_cmds.mjs';

// ---- 参数定义 ----
const SPECS = {
  // 短选项映射: 单字符 -> 长名称
  shortOpts: {
    o: 'output',
    h: 'help',
    c: 'category',
  },
  // 需要值的选项
  withValue: new Set([
    'output',
    'category', 'page', 'page-size', 'sortby', 'order',
    'filters', 'category-id', 'kind',
    'target-type', 'param',
    'namespace',
    'chunk-size',
    'interval', 'timeout',
    'asset-id',
    'title', 'description', 'tags', 'release-at',
    'cover',
  ]),
  // 布尔标志选项
  flags: new Set([
    'help', 'no-proxy', 'include-pages',
    'new-only', 'untagged-only', 'favorite-only', 'group-by-tanks',
    'overwrite', 'write-back',
    'wait',
  ]),
  knownCommands: [
    'info', 'search', 'archive-show', 'category-list',
    'cover',
    'tankoubon-list', 'tankoubon-show',
    'update-metadata',
    'source-list',
    'source-home', 'source-search', 'source-filters',
    'source-download', 'download-url', 'upload',
    'metadata-run', 'task',
  ],
};

// ---- 简单参数解析 ----
function parseArgs(argv) {
  const options = {};   // 带值的选项
  const flags = {};     // 布尔标志
  const args = [];       // 位置参数

  let i = 2; // 跳过 "node main.mjs"
  while (i < argv.length) {
    const raw = argv[i];

    // --
    if (raw === '--') {
      i++;
      while (i < argv.length) args.push(argv[i++]);
      break;
    }

    // --long-opt
    if (raw.startsWith('--')) {
      const eqIdx = raw.indexOf('=');
      let name, value;
      if (eqIdx >= 0) {
        name = raw.slice(2, eqIdx);
        value = raw.slice(eqIdx + 1);
      } else {
        name = raw.slice(2);
        value = undefined;
      }

      if (SPECS.withValue.has(name)) {
        if (value !== undefined) {
          options[name] = value;
        } else if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
          options[name] = argv[++i];
        } else {
          throw new Error(`option --${name} requires a value`);
        }
      } else if (SPECS.flags.has(name)) {
        flags[name] = true;
        if (value !== undefined) {
          // --help=xxx 这类用法忽略值
        }
      } else {
        throw new Error(`unknown option: --${name}`);
      }
      i++;
      continue;
    }

    // -short-opt
    if (raw.startsWith('-') && raw.length > 1) {
      const shortName = raw.slice(1);
      const longName = SPECS.shortOpts[shortName];
      if (!longName) {
        throw new Error(`unknown option: -${shortName}`);
      }

      if (SPECS.withValue.has(longName)) {
        if (i + 1 < argv.length && !argv[i + 1].startsWith('-')) {
          options[longName] = argv[++i];
        } else {
          throw new Error(`option -${shortName} requires a value`);
        }
      } else if (SPECS.flags.has(longName)) {
        flags[longName] = true;
      }
      i++;
      continue;
    }

    // 位置参数
    args.push(raw);
    i++;
  }

  return { options, flags, args };
}

function printUsage() {
  console.log('lanlu-cli [options] <command> [args]');
  console.log('');
  console.log('Environment:');
  console.log('  LANLU_TOKEN   required. Bearer token for authentication');
  console.log('  LANLU_HOST    server URL, default http://localhost:8082');
  console.log('');
  console.log('Options:');
  console.log('  -o, --output <mode>       text|json|pretty-json (default: text)');
  console.log('      --no-proxy            ignore http_proxy / https_proxy');
  console.log('  -h, --help                show this help');
  console.log('');
  console.log('Commands:');
  console.log('  info                      server info');
  console.log('  search <filter>           search archives (--group-by-tanks)');
  console.log('  archive-show <arcid>      show archive metadata');
  console.log('  category-list             list categories');
  console.log('  cover <id>                show cover asset_id for archive/tankoubon');
  console.log('  cover --asset-id <id>     show URL for a known asset_id');
  console.log('  tankoubon-list            list tankoubon collections');
  console.log('  tankoubon-show <id>       show tankoubon detail + archives');
  console.log('  update-metadata <id>    update metadata (--title/--description/--tags/--cover)');
  console.log('  source-list               list source plugins');
  console.log('  source-home <namespace>   source plugin home');
  console.log('  source-search <namespace> <query>');
  console.log('  source-filters <namespace>');
  console.log('  source-download <namespace> <remote-id> --category-id <id>');
  console.log('  download-url <url> --category-id <id>');
  console.log('  upload <file> --category-id <id>');
  console.log('  metadata-run <namespace> <target-id>');
  console.log('  task <id>                 show task detail');
  console.log('');
  console.log('Search flags: --new-only --untagged-only --favorite-only --group-by-tanks');
  console.log('Create commands support --wait [--interval <ms>] [--timeout <ms>].');
}

// ---- 主流程 ----
async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv);
  } catch (e) {
    console.error(`argument error: ${e.message}`);
    printUsage();
    process.exit(1);
  }

  if (opts.flags['help']) {
    printUsage();
    process.exit(0);
  }

  if (opts.args.length === 0) {
    console.error('missing command');
    printUsage();
    process.exit(1);
  }

  const outputMode = opts.options['output'] ?? 'text';
  if (!['text', 'json', 'pretty-json'].includes(outputMode)) {
    console.error(`invalid --output: ${outputMode}`);
    process.exit(1);
  }

  const token = process.env.LANLU_TOKEN ?? '';
  if (!token) {
    console.error('LANLU_TOKEN environment variable is required');
    process.exit(1);
  }

  const host = process.env.LANLU_HOST ?? 'http://localhost:8082';

  const cmd = opts.args[0];
  opts.args = opts.args.slice(1); // 将命令后的参数留给 handler

  if (!SPECS.knownCommands.includes(cmd)) {
    console.error(`unknown command: ${cmd}`);
    printUsage();
    process.exit(1);
  }

  const noProxy = !!opts.flags['no-proxy'];
  const client = new LanluApiClient({ host, token, noProxy });

  try {
    const cmdMap = {
      'info': handleInfo,
      'search': handleSearch,
      'archive-show': handleArchiveShow,
      'category-list': handleCategoryList,
      'cover': handleCover,
      'tankoubon-list': handleTankoubonList,
      'tankoubon-show': handleTankoubonShow,
      'update-metadata': handleUpdateMetadata,
      'source-list': handleSourceList,
      'source-home': handleSourceHome,
      'source-search': handleSourceSearch,
      'source-filters': handleSourceFilters,
      'source-download': handleSourceDownload,
      'download-url': handleDownloadUrl,
      'upload': handleUpload,
      'metadata-run': handleMetadataRun,
      'task': handleTask,
    };

    await cmdMap[cmd](client, opts, outputMode);
  } catch (e) {
    console.error(`error: ${e.message}`);
    process.exit(1);
  }
}

main();
