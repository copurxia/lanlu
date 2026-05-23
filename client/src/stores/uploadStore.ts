import {create} from 'zustand';
import {createJSONStorage, persist} from 'zustand/middleware';
import {createMmkvStorage} from '../storage/zustandMmkvStorage';

export type UploadFile = {
  id: string;
  uri: string;
  name: string;
  size: number;
  type: string;
  progress: number;
  status: 'queued' | 'uploading' | 'success' | 'error' | 'fileExists';
  error?: string;
};

export type DownloadTask = {
  id: string;
  url: string;
  jobId?: number;
  progress: number;
  log: string;
  status: 'pending' | 'downloading' | 'success' | 'error';
  error?: string;
};

type UploadStoreState = {
  uploadFiles: UploadFile[];
  downloadTasks: DownloadTask[];

  addUploadFiles: (files: UploadFile[]) => void;
  updateUploadFile: (id: string, patch: Partial<UploadFile>) => void;
  removeUploadFile: (id: string) => void;
  clearUploadFiles: () => void;

  addDownloadTask: (task: DownloadTask) => void;
  updateDownloadTask: (id: string, patch: Partial<DownloadTask>) => void;
  removeDownloadTask: (id: string) => void;
  clearDownloadTasks: () => void;
};

export const useUploadStore = create<UploadStoreState>()(
  persist(
    (set) => ({
      uploadFiles: [],
      downloadTasks: [],

      addUploadFiles: (files) =>
        set(state => ({uploadFiles: [...state.uploadFiles, ...files]})),

      updateUploadFile: (id, patch) =>
        set(state => ({
          uploadFiles: state.uploadFiles.map(f =>
            f.id === id ? {...f, ...patch} : f,
          ),
        })),

      removeUploadFile: (id) =>
        set(state => ({
          uploadFiles: state.uploadFiles.filter(f => f.id !== id),
        })),

      clearUploadFiles: () => set({uploadFiles: []}),

      addDownloadTask: (task) =>
        set(state => ({downloadTasks: [...state.downloadTasks, task]})),

      updateDownloadTask: (id, patch) =>
        set(state => ({
          downloadTasks: state.downloadTasks.map(d =>
            d.id === id ? {...d, ...patch} : d,
          ),
        })),

      removeDownloadTask: (id) =>
        set(state => ({downloadTasks: state.downloadTasks.filter(d => d.id !== id)})),

      clearDownloadTasks: () => set({downloadTasks: []}),
    }),
    {
      name: 'upload-transfers',
      storage: createJSONStorage(() => createMmkvStorage('upload-transfers')),
      partialize: state => ({
        uploadFiles: [],
        downloadTasks: state.downloadTasks,
      }),
    },
  ),
);
