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
  // Archive 收藏
  static addFavorite = (arcid: string) => favoriteAction('archive', arcid, 'add');
  static removeFavorite = (arcid: string) => favoriteAction('archive', arcid, 'remove');
  static toggleFavorite = (arcid: string, isFav: boolean) =>
    favoriteAction('archive', arcid, isFav ? 'remove' : 'add');

  // Tankoubon 收藏
  static addTankoubonFavorite = (id: string) => favoriteAction('tankoubon', id, 'add');
  static removeTankoubonFavorite = (id: string) => favoriteAction('tankoubon', id, 'remove');
  static toggleTankoubonFavorite = (id: string, isFav: boolean) =>
    favoriteAction('tankoubon', id, isFav ? 'remove' : 'add');
}
