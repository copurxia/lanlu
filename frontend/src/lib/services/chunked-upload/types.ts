// 上传元数据接口
export interface UploadMetadata {
  title?: string;
  tags?: string;
  summary?: string;
  categoryId?: string;
  fileChecksum?: string;
}

// 上传进度回调接口
export interface UploadProgressCallback {
  onProgress: (progress: number) => void;
  onChunkComplete?: (chunkIndex: number, totalChunks: number, uploadedChunks: number) => void;
  onError?: (error: Error, chunkIndex?: number) => void;
}

// 上传结果接口
export interface UploadResult {
  success: boolean;
  taskId?: string;
  error?: string;
}

// 上传状态接口
export interface UploadStatus {
  taskId: string;
  fileName: string;
  fileSize: number;
  totalChunks: number;
  completedChunks: number[];
  status: 'pending' | 'uploading' | 'completed' | 'failed';
  createdAt: string;
  fileHash: string;
}

// 文件验证结果接口
export interface ValidationResult {
  valid: boolean;
  error?: string;
}

// 分片上传会话接口
export interface UploadSession {
  taskId: string;
  fileName: string;
  fileSize: number;
  fileHash: string;
  totalChunks: number;
  createdAt: number;
  metadata?: UploadMetadata;
}

// 分片上传结果接口
export interface ChunkUploadResult {
  success: boolean;
  failedChunks?: number[];
  error?: string;
}
