/**
 * 元数据更新命令: update-metadata
 *
 * 用法:
 *   update-metadata <id> --title "new title" --description "..." --tags "tag1, tag2"
 *   update-metadata <id> --cover 1234 --target-type tankoubon
 *
 * API:
 *   PUT /api/archives/{id}/metadata    — 更新归档元数据
 *   PUT /api/tankoubons/{id}/metadata  — 更新合集元数据
 *
 * 请求体格式：{"title":"...","description":"...","tags":"...","assets":{"cover":"..."}}
 * tags 支持逗号分隔字符串或 JSON 数组
 */

export async function handleUpdateMetadata(client, opts, outputMode) {
  if (opts.args.length < 1) {
    throw new Error('usage: update-metadata <id> [--title] [--description] [--tags] [--release-at] [--cover]');
  }
  const targetId = opts.args[0];
  const targetType = opts.options['target-type'] ?? 'archive';

  const body = buildMetadataBody(opts);

  if (Object.keys(body).length === 0) {
    throw new Error('at least one field to update is required (--title, --description, --tags, --release-at, --cover)');
  }

  const apiPath = targetType === 'tankoubon'
    ? `/api/tankoubons/${encodeURIComponent(targetId)}/metadata`
    : `/api/archives/${encodeURIComponent(targetId)}/metadata`;

  const payload = JSON.stringify(body);
  const respBody = await client.put(apiPath, payload);

  if (outputMode === 'text') {
    try {
      const root = JSON.parse(respBody);
      const success = root.success ?? 0;
      if (success === 1) {
        console.log(`metadata updated for ${targetType} ${targetId}`);
        if (root.archives_patched !== undefined) {
          console.log(`archives patched: ${root.archives_patched}, skipped: ${root.archives_skipped ?? 0}`);
        }
      } else {
        console.log(respBody);
      }
    } catch {
      console.log(respBody);
    }
  } else if (outputMode === 'pretty-json') {
    console.log(JSON.stringify(JSON.parse(respBody), null, 2));
  } else {
    console.log(respBody);
  }
}

function buildMetadataBody(opts) {
  const body = {};

  const title = opts.options['title'];
  if (title !== undefined) body.title = title;

  const description = opts.options['description'];
  if (description !== undefined) body.description = description;

  const tags = opts.options['tags'];
  if (tags !== undefined) {
    // 如果是 JSON 数组格式，原样传数组；否则传字符串
    try {
      const parsed = JSON.parse(tags);
      if (Array.isArray(parsed)) {
        body.tags = parsed;
      } else {
        body.tags = tags;
      }
    } catch {
      body.tags = tags;
    }
  }

  const releaseAt = opts.options['release-at'];
  if (releaseAt !== undefined) body.release_at = releaseAt;

  const cover = opts.options['cover'];
  if (cover !== undefined) {
    body.assets = { cover };
  }

  const namespace = opts.options['namespace'];
  if (namespace !== undefined) body.metadata_namespace = namespace;

  return body;
}
