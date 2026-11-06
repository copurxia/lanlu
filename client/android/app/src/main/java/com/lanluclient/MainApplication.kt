package com.lanluclient

import android.app.Application
import android.os.Build
import android.preference.PreferenceManager
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsDefaults
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlagsProvider
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.soloader.SoLoader

class MainApplication : Application(), ReactApplication {

  override val reactHost: ReactHost by lazy {
    getDefaultReactHost(
      context = applicationContext,
      packageList =
        PackageList(this).packages.apply {
          // Packages that cannot be autolinked yet can be added manually here, for example:
          // add(MyReactNativePackage())
          add(LanluMediaProxyPackage())
        },
    )
  }

  override fun onCreate() {
    super.onCreate()
    CrashLogger.install(this)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
      ExitHistoryRecorder.record(this)
    }
    if (BuildConfig.DEBUG) {
      // Debug builds load JS from Metro. Preset the RN dev host so physical
      // devices do not need Dev Menu / adb reverse on the same LAN.
      PreferenceManager.getDefaultSharedPreferences(this)
        .edit()
        .putString("debug_http_host", "192.168.0.111:8081")
        .commit()
    }
    SoLoader.init(this, OpenSourceMergedSoMapping)
    if (BuildConfig.IS_NEW_ARCHITECTURE_ENABLED) {
      // load() overrides feature flags internally. Overriding them a second time
      // throws "Feature flags cannot be overridden more than once", so use the
      // one-shot internal entry point with our provider instead.
      val featureFlags = object : ReactNativeFeatureFlagsDefaults() {
        override fun enableBridgelessArchitecture(): Boolean = true
        override fun useNativeViewConfigsInBridgelessMode(): Boolean = true
      }
      try {
        val method = DefaultNewArchitectureEntryPoint::class.java.getDeclaredMethod(
          "loadWithFeatureFlags\$ReactAndroid",
          ReactNativeFeatureFlagsProvider::class.java,
        )
        method.isAccessible = true
        method.invoke(DefaultNewArchitectureEntryPoint, featureFlags)
      } catch (missing: NoSuchMethodException) {
        // Older RN variants only expose load(); keep the app bootable there.
        DefaultNewArchitectureEntryPoint.load()
      }
    }
  }
}
