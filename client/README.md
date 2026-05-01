# Lanlu Client

React Native CLI mobile client for Lanlu.

## Current MVP

- Server URL configuration
- Username/password login with Bearer token storage in the device keychain
- Session restore through `/api/auth/me`
- Archive search and paginated library browsing
- Archive detail view with cover, metadata, favorite toggle, and reading entry points
- Image archive reader with horizontal paging and throttled progress updates

The MVP intentionally does not include TOTP/WebAuthn login, uploads, plugin management, user administration, metadata editing, or video/audio/html reader support.

## Development

Install dependencies:

```sh
npm install
```

Start Metro:

```sh
npm start
```

Run Android:

```sh
npm run android
```

For Android emulator access to a Lanlu server running on the host machine, use:

```text
http://10.0.2.2:8082
```

Run iOS on macOS:

```sh
bundle install
bundle exec pod install
npm run ios
```

## Checks

```sh
npx tsc --noEmit
npm run lint
npm test -- --runInBand
```

Android native build requires a local JDK with `JAVA_HOME` configured.
