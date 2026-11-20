package cui.system

import lbase.CuiException

import std.collection.HashMap

public enum HintPriority {
    | Default
    | Normal
    | Override
}

public enum SdlHint {
    | AppId
    | AppName
    | FileDialogDriver
    | ImeImplementedUi
    | MouseFocusClickthrough
    | RenderVSync
    | ReturnKeyHidesIme
    | VideoAllowScreensaver
    | VideoDriver
    | WindowsCloseOnAltF4
    | CustomHint(String)
}

public struct SdlHintSetting {
    public let hint: SdlHint
    public let value: String
    public let priority: HintPriority

    public init(hint: SdlHint, value: String, priority!: HintPriority = HintPriority.Normal) {
        this.hint = hint
        this.value = value
        this.priority = priority
    }
}

public class SdlHints {
    /**
     * Throws `CuiException` when SDL rejects the hint.
     */
    public static func set(hint: SdlHint, value: String): Unit {
        withHintStrings(hint, value, HintPriority.Normal)
    }

    /**
     * Throws `CuiException` when SDL rejects the hint.
     */
    public static func set(setting: SdlHintSetting): Unit {
        withHintStrings(setting.hint, setting.value, setting.priority)
    }

    /**
     * Throws `CuiException` when SDL rejects the hint.
     */
    public static func setBool(
        hint: SdlHint,
        value: Bool,
        priority!: HintPriority = HintPriority.Normal
    ): Unit {
        withHintStrings(hint, boolHintValue(value), priority)
    }

    /**
     * Throws `CuiException` when SDL rejects one of the hints.
     */
    public static func apply(settings: Array<SdlHintSetting>): Unit {
        for (setting in settings) {
            SdlHints.set(setting)
        }
    }

    /**
     * Throws `CuiException` when the hint name is empty.
     */
    public static func get(hint: SdlHint): ?String {
        // P5：进程内提示存储（不再询问 SDL）
        hintStoreGet(checkedHintName(hint))
    }

    /**
     * Throws `CuiException` when the hint name is empty.
     */
    public static func getBool(hint: SdlHint, defaultValue: Bool): Bool {
        match (hintStoreGet(checkedHintName(hint))) {
            case Some(v) => v != "0"
            case None => defaultValue
        }
    }

    /**
     * Returns whether SDL reset a hint value after validating the hint name.
     */
    public static func reset(hint: SdlHint): Bool {
        hintStoreRemove(checkedHintName(hint))
    }

    public static func resetAll(): Unit {
        hintStoreClear()
    }
}

// P5：提示（hints）不再走 SDL，改为进程内存储（OHOS 上这些提示本就无意义）。
private let hintStore = HashMap<String, String>()

private func hintStoreSet(name: String, value: String): Unit {
    hintStore[name] = value
}

private func hintStoreGet(name: String): ?String {
    match (hintStore.get(name)) {
        case Some(v) => Some(v)
        case None => None
    }
}

private func hintStoreRemove(name: String): Bool {
    let had = hintStore.contains(name)
    hintStore.remove(name)
    had
}

private func hintStoreClear(): Unit {
    hintStore.clear()
}
