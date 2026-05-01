import {NativeModules, Platform} from 'react-native';

type LanluMediaProxyModule = {
  createUrl: (uri: string, headers?: Record<string, string>) => Promise<string>;
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
