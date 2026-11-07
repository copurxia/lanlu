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

/**
 * Some CI runners (e.g. CNB in mainland China) cannot reach
 * plugins.gradle.org, which breaks the included React Native Gradle plugin
 * build: it resolves org.gradle.toolchains.foojay-resolver-convention from the
 * Gradle Plugin Portal only. When LANLU_GRADLE_PLUGIN_MIRROR is set, prepend
 * that mirror so plugin resolution succeeds; other environments (GitHub/Gitea
 * runners, dev machines) are left untouched because the variable is unset.
 */
function patchGradlePluginMirror() {
  const mirror = process.env.LANLU_GRADLE_PLUGIN_MIRROR;
  if (!mirror) {
    return;
  }
  const relativePath = 'node_modules/@react-native/gradle-plugin/settings.gradle.kts';
  const file = path.join(root, relativePath);
  if (!fs.existsSync(file)) {
    return;
  }
  let source = fs.readFileSync(file, 'utf8');
  if (source.includes(mirror)) {
    return;
  }
  const anchor = '    gradlePluginPortal()';
  if (!source.includes(anchor)) {
    // Upstream changed the block layout; leave it alone and let the build fail
    // loudly rather than patch blind.
    return;
  }
  source = source.replace(anchor, `    maven { url = uri("${mirror}") }\n${anchor}`);
  fs.writeFileSync(file, source);
  console.log(`[patch-dependencies] added Gradle plugin mirror to ${relativePath}`);
}

patchGradlePluginMirror();
