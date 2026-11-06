/*
 * Reproducible patches for third-party packages that have not caught up with
 * React Native 0.88 / Android Gradle Plugin 9.
 *
 * Keep every patch idempotent and scoped to a single known upstream line so it
 * fails loudly (by leaving the file untouched) once the dependency is fixed.
 */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');

function patchFile(relativePath, replacements) {
  const file = path.join(root, relativePath);
  if (!fs.existsSync(file)) {
    return;
  }
  let source = fs.readFileSync(file, 'utf8');
  const original = source;
  for (const [from, to] of replacements) {
    source = source.split(from).join(to);
  }
  if (source !== original) {
    fs.writeFileSync(file, source);
    console.log(`[patch-dependencies] patched ${relativePath}`);
  }
}

// react-native-vlc-media-player@1.0.98 still requests proguard-android.txt,
// which AGP 9 rejects. The optimize variant is equivalent for this library
// because minifyEnabled is false for release.
patchFile('node_modules/react-native-vlc-media-player/android/build.gradle', [
  [
    "getDefaultProguardFile('proguard-android.txt')",
    "getDefaultProguardFile('proguard-android-optimize.txt')",
  ],
]);
