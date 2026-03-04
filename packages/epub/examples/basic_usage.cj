/**
 * EPUB 解析库使用示例
 */
import epub.*
import epub.models.*

main(): Int64 {
    // 从文件路径打开 EPUB
    let book = Epub.open("/path/to/book.epub")

    // 获取元数据
    println("=== EPUB 元数据 ===")
    if (let Some(title) <- book.metadata.title) {
        println("标题: ${title}")
    }

    if (!book.metadata.creators.isEmpty()) {
        println("作者: ${book.metadata.creators[0]}")
    }

    if (let Some(lang) <- book.metadata.language) {
        println("语言: ${lang}")
    }

    if (let Some(desc) <- book.metadata.description) {
        println("描述: ${desc}")
    }

    // 遍历章节
    println("\n=== 章节列表 ===")
    for (chapter in book.chapters) {
        println("章节: ${chapter.title}")
        println("  文件数: ${chapter.getFileCount()}")
    }

    // 遍历目录
    println("\n=== 目录 ===")
    for (entry in book.tableOfContents.entries) {
        println("- ${entry.title} (${entry.href})")
    }

    // 获取封面
    println("\n=== 封面 ===")
    let coverOpt = book.getCoverBytes()
    match (coverOpt) {
        case Some(data) =>
            println("封面大小: ${data.size} 字节")
        case None =>
            println("未找到封面")
    }

    // 获取资源列表
    println("\n=== 资源列表 ===")
    let resources = book.getResourceList()
    for (res in resources) {
        println("- ${res.id}: ${res.href} (${res.mediaType})")
    }

    // 清理
    book.close()

    return 0
}
