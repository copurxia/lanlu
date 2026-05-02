import {NativeModules, Platform} from 'react-native';

type LanluMediaProxyModule = {
  createUrl: (uri: string, headers?: Record<string, string>) => Promise<string>;
  setSystemBarsHidden?: (hidden: boolean) => void;
  writeTextFile?: (extension: string, text: string) => Promise<string>;
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

export async function createLocalSubtitleFile(text: string, extension = 'ass') {
  if (Platform.OS !== 'android' || !nativeProxy?.writeTextFile || !text.trim()) {
    return undefined;
  }
  return nativeProxy.writeTextFile(extension, text);
}

export function setSystemBarsHidden(hidden: boolean) {
  if (Platform.OS !== 'android' || !nativeProxy?.setSystemBarsHidden) return;
  nativeProxy.setSystemBarsHidden(hidden);
}
