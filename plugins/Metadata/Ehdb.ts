#!/usr/bin/env deno run --allow-net --allow-read --allow-env

import { BasePlugin, PluginInfo, PluginInput, PluginResult } from '../base_plugin.ts';

/**
 * EHDB元数据插件
 * 从本地PostgreSQL数据库查询并获取画廊标签和元数据
 */
class EhdbMetadataPlugin extends BasePlugin {
  private dbClient: any = null;
  private connectionString: string = '';

  getPluginInfo(): PluginInfo {
    return {
      name: "EHDB",
      type: "metadata",
      namespace: "ehdb",
      author: "EHDB Plugin",
      version: "1.0",
      description: "Queries local EHDB PostgreSQL database for gallery metadata. Faster than web scraping.",
      parameters: [
        {
          name: "connection_string",
          type: "string",
          desc: "PostgreSQL connection string (e.g., postgres://user:pass@host:port/database?sslmode=disable)"
        }
      ],
      oneshot_arg: "Gallery URL or GID/Token (Will match this exact gallery)",
      cooldown: 0,
      permissions: ["net", "env"],
      icon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAAEnQAABJ0Ad5mH3gAAAOASURBVDhPjVNbaFRXFF3n3puZyZ3EzJ1HkpIohthAP0InYMAKUUpfVFDylY9Bg1CJ+UllfLSEIoIEtBan7Y9t8KO0pSU0lH74oQZsMWImkSBalUADqR8mTVOTyXMymcfd7nPuNZpo2yzm3DmPfdZZZ+91MDyYJA0g+AMkStY3i8Brn392jjYKIclK7hP0rNzK7XkIIM8BdlRgkdYvvhya7bcUGT0ugKbXNZ4zcsCS+Qoycyl3y39DCL5qoJ+DpUKvM6mwzIcsFQCfjtmfL+LQX5cRa+9AOp12A57Btm1UV1ejoaHBIbTupDB/YB/yg5fcEKDo3VaUnPoWlLZBfg1zOwU6OjqQSr2o1DAMJJNJNDU1OYTBeynMNFbBPHoRwirnxOWgVW2DVhbh4wsQQR2p3VWgxXGX4uWQxJxyFyvLKHpzDzy7tsOz+w1olkMmQfKW+z/Gmc7javxvKC0t5SSywtCfRFplDYlNIRJlES65QYEbRNYQrf77bxFtKRauOYj6+vook8m4IweBAFtNXfl+CtP1FszD56VuLo6J/O/XYT98AL1+FwojQxChSuRuXsV3X55mywbR1taGlpYWlbfx8XHEYjFVFEfhQ2UyCriKAv2sapjIF/+agndZ3dmrZP1GpH/4Fb1eu0XF9vT0UHd3t+onEgkaGxuj8vJy+UieQfPzASxQNqxwyyyD2D5YmoU9PwfP3naETS+i0Siam5vBJOjq6kI8HkdNTQ2y2SzkVmZQXyydPMIEC+y/eRQfuQAU8mreznBVhIAvBFwb+YeLdA+6z0RFRQUmJiZUzFMohVKFr/UUq5jmAU/ofM5KGkWN74HY8MarnBtv8Wq1T350DLquw+PxyO1rIOC3KJicQbZ/SFpeKUGBvVfGchhaZDOEybnIs4U0HTYfOP+OABcVvb29qjCyL2FZlrysTqHJPBY+OMwbpGBJmIPx2g5FbuzYC30ze9KxJEQYmIlWclom1Xh0dBR1dXWKNBwOQxxtP0SJn/qBne+vGlmBXwtHATmujtfDP9nn3Hj9WBn4FefiB3Gi8xM32IFSKA05cvc2Jh894rysKbqCaZq48MWn+OaPrUBjTKUD37+Fqam/EYnwM30OklBK/V8spqYIRh3hB8evd4YH3ZW1YELaEKGE32sQKt6mK7/86M68CHnYhgkTifNqQ21trVKyvsm1gYEBegL+M2W04901FQAAAABJRU5ErkJggg==",
      update_url: "https://git.copur.xyz/copur/lanlu/raw/branch/main/plugins/Metadata/Ehdb.ts"
    };
  }

  protected async runPlugin(input: PluginInput): Promise<void> {
    try {
      this.reportProgress(5, '初始化数据库连接...');
      const params = this.getParams();

      // 获取连接字符串
      this.connectionString = params.connection_string || '';
      if (!this.connectionString) {
        this.outputResult({ success: false, error: 'Connection string is required' });
        return;
      }

      await this.logInfo("run:start", {
        archive_id: input.archiveId || '',
        has_oneshot: !!input.oneshotParam,
        title_len: (input.archiveTitle || '').length,
        has_thumbhash: !!(input.thumbnailHash || ''),
        debug: !!params.debug
      });

      this.reportProgress(20, '建立数据库连接...');

      // 连接数据库
      await this.connectDatabase();

      this.reportProgress(40, '开始搜索画廊...');

      // 从 input 中获取必要信息
      const lrrInfo = {
        archive_title: input.archiveTitle || '',
        existing_tags: input.existingTags || '',
        thumbnail_hash: input.thumbnailHash || '',
        oneshot_param: input.oneshotParam || '',
        archive_id: input.archiveId || ''
      };

      const result = await this.searchGallery(lrrInfo);

      this.reportProgress(100, '元数据获取完成');

      // 关闭数据库连接
      await this.disconnectDatabase();

      this.outputResult(result);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      await this.logError("run:error", { error: errorMessage });
      this.outputResult({ success: false, error: `Plugin execution failed: ${errorMessage}` });

      // 确保关闭数据库连接
      try {
        await this.disconnectDatabase();
      } catch {
        // ignore
      }
    }
  }

  private async connectDatabase(): Promise<void> {
    try {
      // 设置默认环境变量，避免 PGAPPNAME 错误
      Deno.env.set("PGAPPNAME", "EhdbPlugin");

      // 动态导入 PostgreSQL 客户端
      const { Client } = await import("https://deno.land/x/postgres@v0.19.3/mod.ts");

      this.dbClient = new Client(this.connectionString);
      await this.dbClient.connect();
      await this.logInfo("db:connected", {});
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      throw new Error(`Database connection failed: ${errorMessage}`);
    }
  }

  private async disconnectDatabase(): Promise<void> {
    if (this.dbClient) {
      try {
        await this.dbClient.end();
        this.dbClient = null;
      } catch (error) {
        await this.logWarn("db:disconnect_error", { error: String(error) });
      }
    }
  }

  private async searchGallery(lrrInfo: any): Promise<PluginResult> {
    try {
      let gID = "";
      let gToken = "";
      let sourceDomain = "e-hentai.org"; // 默认为 e-hentai.org

      // 从 oneshot 参数提取 GID/Token 和域名
      if (lrrInfo.oneshot_param && lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/)) {
        const match = lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/);
        if (match) {
          gID = match[1];
          gToken = match[2];
          // 检查是否是 exhentai.org
          if (lrrInfo.oneshot_param.includes('exhentai.org')) {
            sourceDomain = 'exhentai.org';
          }
          await this.logInfo("search:use_oneshot", { gID, gToken: `${gToken.slice(0, 6)}…`, domain: sourceDomain });
        }
      }
      // 从 existing_tags 的 source 标签提取 GID/Token 和域名
      else if (lrrInfo.existing_tags && lrrInfo.existing_tags.match(/.*source:\s*(?:https?:\/\/)?e(?:x|-)hentai\.org\/g\/([0-9]*)\/([0-z]*)\/*.*/gi)) {
        const match = lrrInfo.existing_tags.match(/.*source:\s*(?:https?:\/\/)?e(?:x|-)hentai\.org\/g\/([0-9]*)\/([0-z]*)\/*.*/gi);
        if (match) {
          const srcMatch = match[0].match(/g\/([0-9]*)\/([0-z]*)/);
          const domainMatch = match[0].match(/e(?:x|-)hentai\.org/);
          if (srcMatch) {
            gID = srcMatch[1];
            gToken = srcMatch[2];
            // 检查是否是 exhentai.org
            if (domainMatch && domainMatch[0].startsWith('ex')) {
              sourceDomain = 'exhentai.org';
            }
            await this.logInfo("search:use_source_tag", { gID, gToken: `${gToken.slice(0, 6)}…`, domain: sourceDomain });
          }
        }
      }

      // 如果没有 GID，从标题和标签搜索
      if (!gID) {
        const searchResult = await this.lookupGalleryByTitleAndTags(
          lrrInfo.archive_title,
          lrrInfo.existing_tags
        );

        if (searchResult.success) {
          gID = searchResult.data.gID;
          gToken = searchResult.data.gToken;
          await this.logInfo("search:lookup_success", { gID, gToken: `${gToken.slice(0, 6)}…` });
        } else {
          await this.logWarn("search:lookup_failed", { error: searchResult.error });
          return searchResult;
        }
      }

      if (!gID) {
        return { success: false, error: "No matching gallery found in database!" };
      }

      // 从数据库获取标签
      const tagsResult = await this.getTagsFromDatabase(gID);
      if (!tagsResult.success) {
        await this.logWarn("search:gdata_failed", { gID, error: tagsResult.error });
        return tagsResult;
      }

      const hashData: any = { tags: tagsResult.data.tags };

      // 添加 source URL（同时添加两个域名）
      if (hashData.tags) {
        const sourceUrlEx = `https://exhentai.org/g/${gID}/${gToken}`;
        const sourceUrlE = `https://e-hentai.org/g/${gID}/${gToken}`;
        hashData.tags += `, source:${sourceUrlEx}, source:${sourceUrlE}`;
        hashData.title = tagsResult.data.title;
      }

      return { success: true, data: hashData };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Gallery search failed: ${errorMessage}` };
    }
  }

  /**
   * 预处理标题：移除方括号/圆括号内容，提取核心标题
   */
  private preprocessTitle(title: string): { core: string; keywords: string[]; artist: string } {
    let core = title;
    let artist = '';

    // 改进的作者提取：优先匹配包含日文或英文字符的作者标记
    const artistPatterns = [
      // 匹配包含 "スタジオ"、"circle" 或明显作者名称的括号
      /^\s*[\[【\(（]([^)\]】]*?(?:スタジオ|circle|_group|teamAuteur|Artwork|イラスト)[^)\]】]*?)[\]】\)）]\s*/i,
      // 匹配包含日文假名/汉字/英文字母的作者名（排除纯数字和日期）
      /^\s*[\[【\(（]([^\]】\)]*?[あ-んア-ン一-龯a-zA-Z][^\]】\)]*?)[\]】\)）]\s*/,
      // 最后的备选：第一个括号内容
      /^\s*[\[【\(（]([^\]】\)）]+)[\]】\)）]\s*/
    ];

    for (const pattern of artistPatterns) {
      const artistMatch = core.match(pattern);
      if (artistMatch) {
        const extractedArtist = artistMatch[1].trim();
        // 验证提取的作者是否合理（非纯数字，非日期）
        if (!/^\d+$/.test(extractedArtist) && !/^\d{2,4}[-\/]\d{1,2}$/.test(extractedArtist)) {
          artist = extractedArtist;
          core = core.replace(artistMatch[0], '');
          break;
        }
      }
    }

    // 移除常见的后缀标记
    const suffixPatterns = [
      /[\[【\(（][^\]】\)）]*(?:DL|Digital|デジタル|電子|无修正|無修正|中文|汉化|漢化|翻訳|翻译)[^\]】\)）]*[\]】\)）]/gi,
      /[\[【\(（](?:C\d+|COMIC\d*|例大祭|コミケ|Comiket)[^\]】\)）]*[\]】\)）]/gi,
      /[\[【\(（]\d{4}[-\/]\d{1,2}[-\/]?\d{0,2}[\]】\)）]/g,
      /\.(zip|rar|7z|cbz|cbr)$/i,
    ];

    for (const pattern of suffixPatterns) {
      core = core.replace(pattern, '');
    }

    // 移除剩余的方括号内容（保留圆括号中的重要描述）
    core = core.replace(/[\[【][^\]】]*[\]】]/g, ' ');

    // 只移除明确标记的圆括号（保留描述性内容）
    core = core.replace(/[\(（][^\)）]*(?:DL|Digital|翻訳|翻译|C\d+|COMIC)[^\)）]*[\)）]/g, ' ');

    // 清理多余空格
    core = core.replace(/\s+/g, ' ').trim();

    // 提取关键词（改进分词，保留更多有意义的词）
    const keywords = core
      .split(/[\s\-_～~、，]+/)
      .filter(k => k.length >= 2)
      .slice(0, 10);

    return { core, keywords, artist };
  }

  /**
   * 计算标题相似度评分
   */
  private calculateSimilarity(input: string, dbTitle: string, dbTitleJpn: string): number {
    const inputLower = input.toLowerCase();
    const titleLower = dbTitle.toLowerCase();
    const titleJpnLower = (dbTitleJpn || '').toLowerCase();

    let score = 0;

    // 完全包含得高分
    if (titleLower.includes(inputLower) || titleJpnLower.includes(inputLower)) {
      score += 50;
    }

    // 计算关键词匹配
    const inputWords = inputLower.split(/[\s\-_]+/).filter(w => w.length >= 2);
    for (const word of inputWords) {
      if (titleLower.includes(word) || titleJpnLower.includes(word)) {
        score += 10;
      }
    }

    return score;
  }

  private async lookupGalleryByTitleAndTags(title: string, tags: string): Promise<PluginResult> {
    try {
      if (!this.dbClient) {
        return { success: false, error: "Database not connected" };
      }

      // 预处理标题
      const { core, keywords, artist } = this.preprocessTitle(title);
      await this.logInfo("search:preprocess", {
        original: title,
        core: core,
        keywords: keywords,
        artist: artist,
        keyword_count: keywords.length,
        has_japanese: /[あ-んア-ン一-龯]/.test(core)
      });

      // 从 existing_tags 提取 artist
      let tagArtist = '';
      const artistTagMatch = tags.match(/artist:\s*([^,]+)/i);
      if (artistTagMatch) {
        tagArtist = artistTagMatch[1].trim();
      }
      const finalArtist = tagArtist || artist;

      // 策略1: 全文搜索 (使用 title_tsv)
      let result = await this.searchByFullText(core, finalArtist);
      if (result.success) {
        await this.logInfo("search:fulltext_hit", { gID: result.data.gID });
        return result;
      }

      // 策略2: 关键词 trigram 搜索
      if (keywords.length > 0) {
        result = await this.searchByKeywords(keywords, finalArtist);
        if (result.success) {
          await this.logInfo("search:keywords_hit", { gID: result.data.gID });
          return result;
        }
      }

      // 策略3: 模糊匹配 (trigram similarity)
      if (core.length >= 4) {
        result = await this.searchByTrigram(core, finalArtist);
        if (result.success) {
          await this.logInfo("search:trigram_hit", { gID: result.data.gID });
          return result;
        }
      }

      return { success: false, error: 'No gallery found in database' };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Database query failed: ${errorMessage}` };
    }
  }

  /**
   * 策略1: 全文搜索 (使用 title_tsv)
   * artist 为优先匹配条件，匹配不到时回退到纯标题搜索
   * 注意：对日文支持有限，会自动跳过
   */
  private async searchByFullText(core: string, artist: string): Promise<PluginResult> {
    // 构建 tsquery
    const words = core.split(/[\s\-_]+/).filter(w => w.length >= 2);

    // 检查是否包含日文字符（包含日文则跳过全文搜索）
    const hasJapanese = /[あ-んア-ン一-龯]/.test(core);
    if (hasJapanese || words.length === 0) {
      await this.logInfo("search:skip_fulltext", { reason: hasJapanese ? "has_japanese" : "no_words" });
      return { success: false, error: 'Skip fulltext search for Japanese text' };
    }

    const tsquery = words.map(w => w.replace(/['"\\]/g, '')).join(' & ');

    // 如果有 artist，先尝试带 artist 过滤的查询
    if (artist) {
      const artistLower = artist.toLowerCase();
      const queryWithArtist = `
        SELECT gid, token, title, title_jpn,
               ts_rank(title_tsv, to_tsquery('simple', $1)) as rank
        FROM gallery
        WHERE title_tsv @@ to_tsquery('simple', $1)
          AND (tags @> $2::jsonb OR tags @> $3::jsonb)
        ORDER BY rank DESC, posted DESC LIMIT 10
      `;
      try {
        const result = await this.dbClient.queryObject(queryWithArtist, [
          tsquery,
          JSON.stringify([`artist:${artistLower}`]),
          JSON.stringify([`group:${artistLower}`])
        ]);
        if (result.rows && result.rows.length > 0) {
          return this.selectBestMatch(result.rows, core);
        }
      } catch (error) {
        await this.logWarn("search:fulltext_error", { error: String(error) });
        return { success: false, error: 'Fulltext search failed' };
      }
    }

    // 回退：不带 artist 过滤
    const query = `
      SELECT gid, token, title, title_jpn,
             ts_rank(title_tsv, to_tsquery('simple', $1)) as rank
      FROM gallery
      WHERE title_tsv @@ to_tsquery('simple', $1)
      ORDER BY rank DESC, posted DESC LIMIT 10
    `;
    try {
      const result = await this.dbClient.queryObject(query, [tsquery]);
      return this.selectBestMatch(result.rows, core);
    } catch (error) {
      await this.logWarn("search:fulltext_error", { error: String(error) });
      return { success: false, error: 'Fulltext search failed' };
    }
  }

  /**
   * 策略2: 关键词 trigram 搜索
   * artist 为优先匹配条件，匹配不到时回退到纯标题搜索
   */
  private async searchByKeywords(keywords: string[], artist: string): Promise<PluginResult> {
    const conditions = keywords.map((_, i) =>
      `(title ILIKE $${i + 1} OR title_jpn ILIKE $${i + 1})`
    );
    const params = keywords.map(k => `%${k}%`);

    // 如果有 artist，先尝试带 artist 过滤的查询
    if (artist) {
      const artistLower = artist.toLowerCase();
      const idx1 = params.length + 1;
      const idx2 = params.length + 2;
      const queryWithArtist = `
        SELECT gid, token, title, title_jpn
        FROM gallery
        WHERE ${conditions.join(' AND ')}
          AND (tags @> $${idx1}::jsonb OR tags @> $${idx2}::jsonb)
        ORDER BY posted DESC LIMIT 10
      `;
      const paramsWithArtist = [
        ...params,
        JSON.stringify([`artist:${artistLower}`]),
        JSON.stringify([`group:${artistLower}`])
      ];
      const result = await this.dbClient.queryObject(queryWithArtist, paramsWithArtist);
      if (result.rows && result.rows.length > 0) {
        return this.selectBestMatch(result.rows, keywords.join(' '));
      }
    }

    // 回退：不带 artist 过滤
    const query = `
      SELECT gid, token, title, title_jpn
      FROM gallery
      WHERE ${conditions.join(' AND ')}
      ORDER BY posted DESC LIMIT 10
    `;
    const result = await this.dbClient.queryObject(query, params);
    return this.selectBestMatch(result.rows, keywords.join(' '));
  }

  /**
   * 策略3: Trigram 相似度搜索
   * artist 为优先匹配条件，匹配不到时回退到纯标题搜索
   */
  private async searchByTrigram(core: string, artist: string): Promise<PluginResult> {
    // 如果有 artist，先尝试带 artist 过滤的查询
    if (artist) {
      const artistLower = artist.toLowerCase();
      const queryWithArtist = `
        SELECT gid, token, title, title_jpn,
               GREATEST(similarity(title, $1), similarity(title_jpn, $1)) as sim
        FROM gallery
        WHERE (title % $1 OR title_jpn % $1)
          AND (tags @> $2::jsonb OR tags @> $3::jsonb)
        ORDER BY sim DESC, posted DESC LIMIT 10
      `;
      const result = await this.dbClient.queryObject(queryWithArtist, [
        core,
        JSON.stringify([`artist:${artistLower}`]),
        JSON.stringify([`group:${artistLower}`])
      ]);
      if (result.rows && result.rows.length > 0) {
        return this.selectBestMatch(result.rows, core);
      }
    }

    // 回退：不带 artist 过滤
    const query = `
      SELECT gid, token, title, title_jpn,
             GREATEST(similarity(title, $1), similarity(title_jpn, $1)) as sim
      FROM gallery
      WHERE (title % $1 OR title_jpn % $1)
      ORDER BY sim DESC, posted DESC LIMIT 10
    `;
    const result = await this.dbClient.queryObject(query, [core]);
    return this.selectBestMatch(result.rows, core);
  }

  /**
   * 从多个候选结果中选择最佳匹配
   * 相似度低于阈值的结果会被抛弃
   * 注意：对日文标题降低阈值以提高匹配成功率
   */
  // Higher threshold to reduce false-positive matches when only generic tokens overlap.
  private static readonly MIN_SIMILARITY_SCORE = 35;

  private selectBestMatch(rows: any[], input: string): PluginResult {
    if (!rows || rows.length === 0) {
      return { success: false, error: 'No results found' };
    }

    // 计算每个结果的相似度评分
    let bestRow = rows[0];
    let bestScore = this.calculateSimilarity(input, bestRow.title, bestRow.title_jpn);

    for (let i = 1; i < rows.length; i++) {
      const row = rows[i];
      const score = this.calculateSimilarity(input, row.title, row.title_jpn);
      if (score > bestScore) {
        bestScore = score;
        bestRow = row;
      }
    }

    // 相似度过低则抛弃
    if (bestScore < EhdbMetadataPlugin.MIN_SIMILARITY_SCORE) {
      return {
        success: false,
        error: `Best match score (${bestScore}) below threshold (${EhdbMetadataPlugin.MIN_SIMILARITY_SCORE})`
      };
    }

    return {
      success: true,
      data: {
        gID: bestRow.gid.toString(),
        gToken: bestRow.token.trim(),
        title: bestRow.title,
        title_jpn: bestRow.title_jpn
      }
    };
  }

  private async getTagsFromDatabase(gID: string): Promise<PluginResult> {
    try {
      if (!this.dbClient) {
        return { success: false, error: "Database not connected" };
      }

      // 查询画廊信息（包含 JSONB 标签）
      const galleryQuery = `
        SELECT gid, token, title, title_jpn, category, uploader, posted, tags
        FROM gallery
        WHERE gid = $1
      `;
      const galleryResult = await this.dbClient.queryObject(galleryQuery, [parseInt(gID)]);

      if (!galleryResult.rows || galleryResult.rows.length === 0) {
        return { success: false, error: 'Gallery not found in database' };
      }

      const gallery = galleryResult.rows[0];
      const tags: string[] = [];

      // 从 JSONB 字段提取标签
      if (gallery.tags && Array.isArray(gallery.tags)) {
        for (const tag of gallery.tags) {
          tags.push(tag);
        }
      }

      // 添加分类标签
      if (gallery.category) {
        tags.push(`category:${gallery.category.toLowerCase()}`);
      }

      // 添加上传者
      if (gallery.uploader) {
        tags.push(`uploader:${gallery.uploader}`);
      }

      const title = gallery.title_jpn || gallery.title;

      await this.logInfo("db:tags_fetched", {
        gID,
        tag_count: tags.length,
        has_title: !!title
      });

      return {
        success: true,
        data: {
          tags: tags.join(', '),
          title: title
        }
      };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Failed to fetch tags: ${errorMessage}` };
    }
  }
}

// 运行插件
if (import.meta.main) {
  const plugin = new EhdbMetadataPlugin();
  await plugin.handleCommand();
}
