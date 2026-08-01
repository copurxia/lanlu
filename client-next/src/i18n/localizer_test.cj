package lanlu_client_next.i18n

import cui.LocalePreference

@Test
func languagePreferencesNormalizeAndResolve(): Unit {
    @Expect(normalizeLanguagePreference("invalid"), LANGUAGE_SYSTEM)
    @Expect(supportedLanguageForTag("zH_Hans_CN"), LANGUAGE_ZH)
    @Expect(resolveLanguage(LANGUAGE_ZH, []), LANGUAGE_ZH)
    @Expect(resolveLanguage(LANGUAGE_SYSTEM, [LocalePreference("zh", country: Some("CN"))]), LANGUAGE_ZH)
    @Expect(resolveLanguage(LANGUAGE_SYSTEM, [LocalePreference("en", country: Some("US"))]), LANGUAGE_EN)
    @Expect(resolveLanguage(LANGUAGE_SYSTEM, []), LANGUAGE_ZH)
}

@Test
func localizerFallsBackAndInterpolates(): Unit {
    let localizer = Localizer()
    @Expect(localizer.text(LANGUAGE_EN, "language.systemDetail", params: [("language", "English")]),
        "Currently using: English")
    @Expect(localizer.text(LANGUAGE_EN, "missing.key"), "missing.key")
    @Expect(localizer.chineseKeyCount(), localizer.englishKeyCount())
    @Expect(localizer.catalogsMatch())
    @Expect(localizer.hasKey(LANGUAGE_ZH, "language.title"))
    @Expect(localizer.hasKey(LANGUAGE_EN, "language.title"))
}
