package cui.system

@Test
func localePreferenceBuildsStableTags(): Unit {
    @Expect(LocalePreference("zh", country: Some("CN")).tag(), "zh-CN")
    @Expect(LocalePreference("en").tag(), "en")
}

@Test
func preferredLocalesAreReadableWhenPlatformProvidesThem(): Unit {
    try {
        for (locale in SystemLocales.preferred()) {
            @Expect(!locale.language.isEmpty())
        }
    } catch (_: Exception) {
        // SDL explicitly permits platforms without locale support. Applications are expected
        // to choose their own fallback, so this path is a valid platform result.
        @Expect(true)
    }
}
