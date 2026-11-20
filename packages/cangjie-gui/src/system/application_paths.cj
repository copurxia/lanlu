package cui.system

import lbase.CuiException

import std.env.getVariable
import std.fs.{Directory, Path}

// P5：应用路径不再经过 SDL。OHOS 上应用只有私有目录（HOME），
// 其他平台的 base/cwd/pref 语义在这里用 HOME 推导。

public enum UserFolder {
    | Home
    | Desktop
    | Documents
    | Downloads
    | Music
    | Pictures
    | PublicShare
    | SavedGames
    | Screenshots
    | Templates
    | Videos
}

public class ApplicationPaths {
    public static func basePath(): ?String {
        getVariable("HOME")
    }

    public static func currentDirectory(): String {
        // OHOS 应用没有传统意义上的 cwd，用 HOME 代替
        getVariable("HOME") ?? "."
    }

    /// 偏好目录：HOME/pref/<org>/<app>/（自动创建）
    public static func preferencePath(org: String, app: String): String {
        ensurePathLabel(org, "Organization")
        ensurePathLabel(app, "Application")
        let home = getVariable("HOME") ?? "."
        let path = home + "/pref/" + org + "/" + app + "/"
        try {
            Directory.create(Path(path), recursive: true)
        } catch (_: Exception) {}
        path
    }

    /// OHOS 上只有应用私有目录：Home 映射到 HOME，其余不存在。
    public static func userFolder(folder: UserFolder): ?String {
        match (folder) {
            case UserFolder.Home => getVariable("HOME")
            case _ => None
        }
    }
}

/**
 * Throws `CuiException` when a preference path label is empty.
 */
private func ensurePathLabel(value: String, name: String): Unit {
    if (value.size <= 0) {
        throw CuiException("${name} name cannot be empty.")
    }
}
