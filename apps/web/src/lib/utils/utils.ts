import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function formatFileSize(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

export function getProgressPercentage(progress: number): string {
  return Math.round(progress * 100) + '%';
}

export function formatDate(dateString: string, unknownLabel: string = 'Unknown'): string {
  if (!dateString) return unknownLabel;
  try {
    return new Date(dateString).toLocaleString();
  } catch {
    return dateString;
  }
}