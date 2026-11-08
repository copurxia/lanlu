-- lanlu task-4 验证种子：500 archives，每条 metadata（title 带编号）+ 3 个标签
BEGIN;
INSERT INTO categories (catid, name, scan_path) VALUES ('CAT_T4', 'task4-seed', '/tmp') ON CONFLICT (catid) DO NOTHING;
INSERT INTO tags (namespace, name) VALUES ('', 'seed_author_a'), ('', 'seed_author_b'), ('', 'seed_author_c'), ('artist', 'seed_artist_x')
ON CONFLICT (namespace, name) DO NOTHING;

INSERT INTO archives (arcid, filename, category_id, relative_path, pagecount, thumbhash, file_size)
SELECT 'ARC_T4_' || g, 'file_' || g || '.zip', (SELECT id FROM categories WHERE catid='CAT_T4'), '', (g % 50) + 1, 'th', 2048 * g
FROM generate_series(1, 500) g
ON CONFLICT (arcid) DO NOTHING;

-- metadata_objects: title = '漫画标题编号00X'
INSERT INTO metadata_objects (entity_type, entity_id, title, description)
SELECT 'archive', 'ARC_T4_' || g, '漫画标题编号' || lpad(g::text, 3, '0'), '种子简介 ' || g
FROM generate_series(1, 500) g
ON CONFLICT (entity_type, entity_id) DO NOTHING;

-- metadata_tags: 每档案 3 个标签（循环取 4 个标签池）
INSERT INTO metadata_tags (metadata_id, tag)
SELECT mo.id, t.tag
FROM metadata_objects mo
CROSS JOIN (VALUES ('seed_author_a'), ('seed_author_b'), ('seed_author_c'), ('artist:seed_artist_x')) AS t(tag)
WHERE mo.entity_type = 'archive' AND mo.entity_id LIKE 'ARC_T4_%'
ON CONFLICT (metadata_id, tag) DO NOTHING;

-- 每档案只留 2 个标签（删掉第 4 个）
DELETE FROM metadata_tags mt
USING metadata_objects mo
WHERE mt.metadata_id = mo.id AND mo.entity_type='archive' AND mo.entity_id LIKE 'ARC_T4_%' AND mt.tag = 'artist:seed_artist_x'
  AND mo.id % 2 = 1;

COMMIT;
-- 触发器会同步 archive_search_docs；验证行数
SELECT 'docs_after_seed=' || count(*) FROM archive_search_docs WHERE arcid LIKE 'ARC_T4_%';
