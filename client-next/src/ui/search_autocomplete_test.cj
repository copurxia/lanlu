package lanlu_client_next.ui

@Test
func autocompleteUsesLastWhitespaceSeparatedToken(): Unit {
    @Expect(lastAutocompleteToken("  title  female:swi"), "female:swi")
    @Expect(lastAutocompleteToken("artist:foo\ttag"), "tag")
    @Expect(lastAutocompleteToken("   "), "")
}

@Test
func autocompleteSelectionReplacesOnlyLastToken(): Unit {
    @Expect(replaceAutocompleteToken("title female:swi", "female:swimsuit"), "title female:swimsuit")
    @Expect(replaceAutocompleteToken("  artist:foo\ttag  ", "male:glasses"), "artist:foo male:glasses")
    @Expect(replaceAutocompleteToken("", "language:chinese"), "language:chinese")
}
