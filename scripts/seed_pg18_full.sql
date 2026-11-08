-- PG18 全量业务级虚拟数据：13,335 归档 + 元数据 + 标签 + 封面 + 触发器同步验证
BEGIN;
-- 分类


-- 13,335 归档（生产同量级）
INSERT INTO archives (arcid, filename, relative_path, file_size, pagecount, archive_type, category_id)
SELECT
  'arc' || g,
  CASE WHEN g % 3 = 0 THEN '漫画标题编号' || lpad(g::text, 6, '0') || '.zip'
       WHEN g % 3 = 1 THEN 'file_' || g || '.zip'
       ELSE 'novel_series_' || g % 500 || '_vol' || g % 40 || '.zip' END,
  '/data/vol' || (g % 100) || '/arc' || g || '.zip',
  1024 * (g % 9000 + 100),
  g % 220 + 1,
  'archive',
  (SELECT id FROM categories WHERE catid='cat1')
FROM generate_series(1, 13335) g;

-- 元数据主体（每归档 1 条）
INSERT INTO metadata_objects (entity_type, entity_id, title, description, extra_data)
SELECT 'archive', 'arc' || g,
  CASE WHEN g % 3 = 0 THEN '漫画标题编号' || lpad(g::text, 6, '0')
       WHEN g % 3 = 1 THEN 'file_' || g
       ELSE 'novel_series_' || g % 500 END,
  'summary 文本 ' || g || '：作者' || (g % 200) || ' 的测试简介',
  jsonb_build_object('Parody', 'parody_' || g % 30, 'Artist', 'artist_' || g % 150, 'Pages', g % 220 + 1)
FROM generate_series(1, 13335) g;

-- 标签字典（每归档 3~5 个，含中英日多语言样例）
INSERT INTO metadata_tags (metadata_id, tag)
SELECT mo.id, t.tag
FROM metadata_objects mo
CROSS JOIN LATERAL (
  SELECT 'namespace_' || (g2 % 8) || ':' ||
    CASE g2 % 10
      WHEN 0 THEN '全彩'
      WHEN 1 THEN '中文'
      WHEN 2 THEN '単行本'
      WHEN 3 THEN 'artist_' || ((regexp_replace(mo.entity_id, '[^0-9]', '', 'g'))::bigint % 150)
      WHEN 4 THEN 'female:' || (g2 % 60)
      WHEN 5 THEN 'male:' || (g2 % 40)
      WHEN 6 THEN 'parody_' || ((regexp_replace(mo.entity_id, '[^0-9]', '', 'g'))::bigint % 30)
      WHEN 7 THEN '语言:' || CASE g2 % 3 WHEN 0 THEN '中文' WHEN 1 THEN '日本語' ELSE 'english' END
      WHEN 8 THEN 'group_' || (g2 % 25)
      ELSE 'theme_' || (g2 % 35)
    END AS tag
  FROM generate_series(1, 3 + ((regexp_replace(mo.entity_id, '[^0-9]', '', 'g'))::bigint % 3)) g2
) t
WHERE mo.entity_type = 'archive';

-- 封面资产（每归档 1 个）+ 关联
INSERT INTO assets (kind, original_filename, content_type, file_ext, byte_size, thumbhash)
SELECT 'cover', 'cover_arc' || g || '.webp', 'image/webp', 'webp', 2048 * (g % 90 + 10), 'thumbhash_' || g
FROM generate_series(1, 13335) g;

INSERT INTO metadata_assets (metadata_id, slot, asset_id)
SELECT mo.id, 0, a.id
FROM metadata_objects mo
JOIN archives arc ON arc.arcid = mo.entity_id
JOIN LATERAL (SELECT id FROM assets ORDER BY id OFFSET arc.id - 1 LIMIT 1) a ON true
WHERE mo.entity_type = 'archive';

COMMIT;