package cui.system

import lbase.CuiException

import std.env.getVariable

@Test
func userFolderMapsOnlyHome(): Unit {
    // P5：应用路径不再经过 SDL（原 userFolderCode/SDL_FOLDER_* 已移除）。
    // 现行口径：只有 Home 映射 HOME；其余平台目录在 OHOS 私有目录模型下恒为 None。
    match (ApplicationPaths.userFolder(UserFolder.Home)) {
        case Some(value) => @Expect(value.size > 0, true)
        case None => @Expect(getVariable("HOME").isNone(), true)
    }
    @Expect(ApplicationPaths.userFolder(UserFolder.Desktop).isNone(), true)
    @Expect(ApplicationPaths.userFolder(UserFolder.Documents).isNone(), true)
    @Expect(ApplicationPaths.userFolder(UserFolder.Downloads).isNone(), true)
    @Expect(ApplicationPaths.userFolder(UserFolder.PublicShare).isNone(), true)
    @Expect(ApplicationPaths.userFolder(UserFolder.Videos).isNone(), true)
}

@Test
func preferencePathRejectsEmptyLabels(): Unit {
    @Expect(preferencePathFails("", "Demo"))
    @Expect(preferencePathFails("CUI", ""))
}

@Test
func currentDirectoryReturnsPathLikeValue(): Unit {
    let path = ApplicationPaths.currentDirectory()

    @Expect(path.size > 0)
}

private func preferencePathFails(org: String, app: String): Bool {
    try {
        let _ = ApplicationPaths.preferencePath(org, app)
        false
    } catch (e: CuiException) {
        true
    }
}
