package lrr4cj.archivehandler

import std.collection.*
import lrr4cj.models.ArchiveTypes

/**
 * 档案处理器工厂
 * 负责根据类型或路径获取对应的处理器
 */
public class ArchiveHandlerFactory {
    // 单例实例
    private static var instance: ?ArchiveHandlerFactory = None

    // 已注册的处理器列表（按优先级排序）
    private var handlers: ArrayList<ArchiveHandler>

    // 类型到处理器的映射
    private var typeMap: HashMap<String, ArchiveHandler>

    private init() {
        handlers = ArrayList<ArchiveHandler>()
        typeMap = HashMap<String, ArchiveHandler>()
    }

    /**
     * 获取工厂单例
     */
    public static func getInstance(): ArchiveHandlerFactory {
        match (instance) {
            case Some(inst) => return inst
            case None =>
                let newInstance = ArchiveHandlerFactory()
                // 注册默认处理器（按优先级顺序）
                newInstance.registerHandler(FolderHandler())
                newInstance.registerHandler(PdfHandler())
                newInstance.registerHandler(EpubHandler())
                newInstance.registerHandler(ArchiveFileHandler())  // 放最后作为默认
                instance = Some(newInstance)
                return newInstance
        }
    }

    /**
     * 注册新的处理器
     */
    public func registerHandler(handler: ArchiveHandler): Unit {
        handlers.add(handler)
        typeMap[handler.getType()] = handler
    }

    /**
     * 根据类型获取处理器
     */
    public func getHandlerByType(archiveType: String): ArchiveHandler {
        match (typeMap.get(archiveType)) {
            case Some(handler) => return handler
            case None =>
                // 默认返回压缩包处理器
                return typeMap.get(ArchiveTypes.ARCHIVE).getOrThrow()
        }
    }

    /**
     * 根据文件路径自动检测并获取处理器
     */
    public func getHandlerByPath(filePath: String): ArchiveHandler {
        for (handler in handlers) {
            if (handler.canHandle(filePath)) {
                return handler
            }
        }
        // 默认返回压缩包处理器
        return typeMap.get(ArchiveTypes.ARCHIVE).getOrThrow()
    }

    /**
     * 检测文件路径对应的类型
     */
    public func detectType(filePath: String): String {
        return getHandlerByPath(filePath).getType()
    }
}
