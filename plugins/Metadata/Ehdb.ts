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
      icon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAAEnQAABJ0Ad5mH3gAAAOASURBVDhPjVNbaFRXFF3n3puZyZ3EzJ1HkpIohthAP0InYMAKUUpfVFDylY9Bg1CJ+UllfLSEIoIEtBan7Y9t8KO0pSU0lH74oQZsMWImkSBalUADqR8mTVOTyXMymcfd7nPuNZpo2yzm3DmPfdZZZ+91MDyYJA0g+AMkStY3i8Brn392jjYKIclK7hP0rNzK7XkIIM8BdlRgkdYvvhya7bcUGT0ugKbXNZ4zcsCS+Qoycyl3y39DCL5qoJ+DpUKvM6mwzIcsFQCfjtmfL+LQX5cRa+9AOp12A57Btm1UV1ejoaHBIbTupDB/YB/yg5fcEKDo3VaUnPoWlLZBfg1zOwU6OjqQSr2o1DAMJJNJNDU1OYTBeynMNFbBPHoRwirnxOWgVW2DVhbh4wsQQR2p3VWgxXGX4uWQxJxyFyvLKHpzDzy7tsOz+w1olkMmQfKW+z/Gmc7javxvKC0t5SSywtCfRFplDYlNIRJlES65QYEbRNYQrf77bxFtKRauOYj6+vook8m4IweBAFtNXfl+CtP1FszD56VuLo6J/O/XYT98AL1+FwojQxChSuRuXsV3X55mywbR1taGlpYWlbfx8XHEYjFVFEfhQ2UyCriKAv2sapjIF/+agndZ3dmrZP1GpH/4Fb1eu0XF9vT0UHd3t+onEgkaGxuj8vJy+UieQfPzASxQNqxwyyyD2D5YmoU9PwfP3naETS+i0Siam5vBJOjq6kI8HkdNTQ2y2SzkVmZQXyydPMIEC+y/eRQfuQAU8mreznBVhIAvBFwb+YeLdA+6z0RFRQUmJiZUzFMohVKFr/UUq5jmAU/ofM5KGkWN74HY8MarnBtv8Wq1T350DLquw+PxyO1rIOC3KJicQbZ/SFpeKUGBvVfGchhaZDOEybnIs4U0HTYfOP+OABcVvb29qjCyL2FZlrysTqHJPBY+OMwbpGBJmIPx2g5FbuzYC30ze9KxJEQYmIlWclom1Xh0dBR1dXWKNBwOQxxtP0SJn/qBne+vGlmBXwtHATmujtfDP9nn3Hj9WBn4FefiB3Gi8xM32IFSKA05cvc2Jh894rysKbqCaZq48MWn+OaPrUBjTKUD37+Fqam/EYnwM30OklBK/V8spqYIRh3hB8evd4YH3ZW1YELaEKGE32sQKt6mK7/86M68CHnYhgkTifNqQ21trVKyvsm1gYEBegL+M2W04901FQAAAABJRU5ErkJggg=="
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

      // 从 oneshot 参数提取 GID/Token
      if (lrrInfo.oneshot_param && lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/)) {
        const match = lrrInfo.oneshot_param.match(/.*\/g\/([0-9]*)\/([0-z]*)\/*.*/);
        if (match) {
          gID = match[1];
          gToken = match[2];
          await this.logInfo("search:use_oneshot", { gID, gToken: `${gToken.slice(0, 6)}…` });
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

      // 添加 source URL
      if (hashData.tags) {
        const sourceUrl = `e-hentai.org/g/${gID}/${gToken}`;
        hashData.tags += `, source:${sourceUrl}`;
        hashData.title = tagsResult.data.title;
      }

      return { success: true, data: hashData };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Gallery search failed: ${errorMessage}` };
    }
  }

  private async lookupGalleryByTitleAndTags(title: string, tags: string): Promise<PluginResult> {
    try {
      if (!this.dbClient) {
        return { success: false, error: "Database not connected" };
      }

      // 提取 artist 标签
      const artistMatch = tags.match(/.*artist:\s?([^,]*),*.*/gi);
      let artistFilter = '';
      if (artistMatch && artistMatch[0]) {
        const artist = artistMatch[0].replace(/.*artist:\s?([^,]*),*.*/gi, '$1').trim();
        if (/^[\x00-\x7F]*$/.test(artist)) {
          artistFilter = artist;
        }
      }

      // 构建查询
      let query = `
        SELECT gid, token, title, title_jpn
        FROM gallery
        WHERE 1=1
      `;

      const params: any[] = [];
      let paramIndex = 1;

      // 标题搜索
      if (title) {
        query += ` AND (title ILIKE $${paramIndex} OR title_jpn ILIKE $${paramIndex})`;
        params.push(`%${title}%`);
        paramIndex++;
      }

      // Artist 标签过滤（使用 JSONB 查询）
      if (artistFilter) {
        query += ` AND EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(tags) AS tag
          WHERE tag = $${paramIndex}
        )`;
        params.push(`artist:${artistFilter}`);
        paramIndex++;
      }

      // 按发布时间倒序排列，限制 1 个结果
      query += ` ORDER BY posted DESC LIMIT 1`;

      await this.logInfo("search:query", { title: title.slice(0, 100), artist: artistFilter });

      const result = await this.dbClient.queryObject(query, params);

      if (result.rows && result.rows.length > 0) {
        const row = result.rows[0];
        return {
          success: true,
          data: {
            gID: row.gid.toString(),
            gToken: row.token,
            title: row.title,
            title_jpn: row.title_jpn
          }
        };
      }

      return { success: false, error: 'No gallery found in database' };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      return { success: false, error: `Database query failed: ${errorMessage}` };
    }
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
