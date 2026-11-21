import {Passkey, PasskeyCreateResult, PasskeyGetResult} from 'react-native-passkey';

function serializeRegistrationCredential(result: PasskeyCreateResult) {
  return {
    id: result.id,
    rawId: result.rawId,
    clientDataJSON: result.response.clientDataJSON,
    attestationObject: result.response.attestationObject,
    transports: result.response.transports || [],
  };
}

function serializeAuthenticationCredential(result: PasskeyGetResult) {
  return {
    id: result.id,
    rawId: result.rawId || '',
    clientDataJSON: result.response.clientDataJSON,
    authenticatorData: result.response.authenticatorData,
    signature: result.response.signature,
    userHandle: result.response.userHandle || '',
  };
}

export const PasskeyModule = {
  isSupported(): boolean {
    return Passkey.isSupported();
  },

  async register(publicKey: Record<string, unknown>) {
    const result = await Passkey.create(publicKey as unknown as Parameters<typeof Passkey.create>[0]);
    return serializeRegistrationCredential(result);
  },

  async authenticate(publicKey: Record<string, unknown>) {
    const result = await Passkey.get(publicKey as unknown as Parameters<typeof Passkey.get>[0]);
    return serializeAuthenticationCredential(result);
  },
};
