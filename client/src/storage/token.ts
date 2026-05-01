import * as Keychain from 'react-native-keychain';

const TOKEN_SERVICE = 'lanlu.authToken';
const TOKEN_USERNAME = 'lanlu';

function getTokenService(serverId?: string | null): string {
  return serverId ? `${TOKEN_SERVICE}.${serverId}` : TOKEN_SERVICE;
}

export async function getStoredToken(serverId?: string | null): Promise<string | null> {
  const credentials = await Keychain.getGenericPassword({
    service: getTokenService(serverId),
  });
  return credentials ? credentials.password : null;
}

export async function setStoredToken(token: string, serverId?: string | null): Promise<void> {
  await Keychain.setGenericPassword(TOKEN_USERNAME, token, {
    service: getTokenService(serverId),
    accessible: Keychain.ACCESSIBLE.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  });
}

export async function clearStoredToken(serverId?: string | null): Promise<void> {
  await Keychain.resetGenericPassword({service: getTokenService(serverId)});
}
