// 收藏功能服务 - 用户级别的档案收藏管理
import { apiClient } from '../api';

type EntityType = 'archive' | 'tankoubon';

const ENTITY_CONFIG = {
  archive: { path: 'archives', label: '收藏' },
  tankoubon: { path: 'tankoubons', label: '合集收藏' }
} as const;

/**
 * 通用收藏操作
 */
async function favoriteAction(
  type: EntityType,
  id: string,
  action: 'add' | 'remove'
): Promise<boolean> {
  const { path, label } = ENTITY_CONFIG[type];
  const method = action === 'add' ? 'put' : 'delete';

  try {
    const response = await apiClient[method](`/api/${path}/${id}/favorite`);
    return response.data.success === 1;
  } catch (error) {
    console.error(`${action === 'add' ? '添加' : '取消'}${label}失败:`, error);
    return false;
  }
}

export class FavoriteService {
  static setFavorite(type: EntityType, id: string, shouldFavorite: boolean): Promise<boolean> {
    return favoriteAction(type, id, shouldFavorite ? 'add' : 'remove');
  }
}
