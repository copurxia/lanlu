import {NativeModules, Platform} from 'react-native';

type LanluMediaProxyModule = {
  createUrl: (uri: string, headers?: Record<string, string>) => Promise<string>;
  createPageUrl?: (uri: string, headers: Record<string, string> | undefined, path: string) => Promise<string>;
  setSystemBarsHidden?: (hidden: boolean, edgeToEdge: boolean) => void;
  shareTextFile?: (extension: string, fileName: string, text: string, title: string) => Promise<string>;
  writeTextFile?: (extension: string, text: string) => Promise<string>;
  uploadFileChunk?: (
    sourceUri: string,
    targetUrl: string,
    headers: Record<string, string> | undefined,
    start: number,
    length: number,
  ) => Promise<string>;
};

const nativeProxy = NativeModules.LanluMediaProxy as LanluMediaProxyModule | undefined;

export async function createProxiedMediaUrl(
  uri: string,
  headers?: Record<string, string>,
) {
  if (Platform.OS !== 'android' || !nativeProxy || !headers?.Authorization) {
    return undefined;
  }
  return nativeProxy.createUrl(uri, headers);
}

export async function createProxiedPageUrl(
  uri: string,
  path: string,
  headers?: Record<string, string>,
) {
  if (Platform.OS !== 'android' || !nativeProxy?.createPageUrl || !headers?.Authorization || !path.trim()) {
    return undefined;
  }
  return nativeProxy.createPageUrl(uri, headers, path);
}

export async function createLocalSubtitleFile(text: string, extension = 'ass') {
  if (Platform.OS !== 'android' || !nativeProxy?.writeTextFile || !text.trim()) {
    return undefined;
  }
  return nativeProxy.writeTextFile(extension, text);
}

export async function shareLocalTextFile(
  text: string,
  extension = 'txt',
  fileName = 'lanlu-log',
  title = fileName,
) {
  if (Platform.OS !== 'android' || !nativeProxy?.shareTextFile) {
    return undefined;
  }
  return nativeProxy.shareTextFile(extension, fileName, text, title);
}

export function setSystemBarsHidden(hidden: boolean, edgeToEdge = true) {
  if (Platform.OS !== 'android' || !nativeProxy?.setSystemBarsHidden) return;
  nativeProxy.setSystemBarsHidden(hidden, edgeToEdge);
}

export async function uploadLocalFileChunk(
  sourceUri: string,
  targetUrl: string,
  headers: Record<string, string> | undefined,
  start: number,
  length: number,
) {
  if (Platform.OS !== 'android' || !nativeProxy?.uploadFileChunk) {
    return false;
  }
  await nativeProxy.uploadFileChunk(sourceUri, targetUrl, headers, start, length);
  return true;
}
