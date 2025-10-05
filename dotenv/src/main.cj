package dotenv

import std.collection.*
import std.env.*
import std.fs.*
import std.io.*
import std.regex.*

internal enum ReadUntilMode {

    | Include // 读取并包含在结果中
    | Skip // 读取但不包含在结果中
    | Exclude // 不读取

}

internal class TextReader {
    
    private var input: String
    private var cursor: Int64 = 0

    public TextReader(input: String) {
        this.input = input
    }

    func skip() {
        this.cursor += 1
    }
    
    func skipUntil(rune: Rune, skipTarget!: Bool = false) {
        while (this.readable() && this.peek() != rune) {
            this.skip()
        }
        if (this.readable() && skipTarget) {
            this.skip()
        }
    }
    
    func skipWhitespace() {
        while (this.readable() && this.peek().isAsciiWhiteSpace() && this.peek() != r'\n') {
            this.skip()
        }
    }
    
    func read(): Rune {
        let result = this.input[this.cursor]
        this.cursor += 1
        return Rune(result)
    }

    func readUntil(rune: Rune, mode!: ReadUntilMode = ReadUntilMode.Include): String {
        let result = StringBuilder()
        while (this.readable() && this.peek() != rune) {
            result.append(this.read())
        }
        match (mode) {
            case ReadUntilMode.Include => 
                if (this.readable()) {
                    result.append(this.read())
                }
            case ReadUntilMode.Skip => 
                if (this.readable()) {
                    this.skip()
                }
            case ReadUntilMode.Exclude => ()
        }
        return result.toString()
    }

    func peek(): Rune {
        return Rune(this.input[this.cursor])
    }

    func readable(): Bool {
        return this.input.size > this.cursor
    }

}

/// Dotenv 类，用于加载 .env 文件中的环境变量
/// 类似于 Node.js 的 require('dotenv').config()
public class Dotenv {
    
    /// 从 .env 文件加载环境变量
    public static func config(): Map<String, String> {
        return config(".env")
    }
    
    /// 从指定路径加载环境变量文件
    /// @param path .env 文件的路径
    /// @return 加载的环境变量
    public static func config(path: String): Map<String, String> {
        let envPath = Path(path)

        let loaded = HashMap<String, String>()
        
        try {
            let file = File(envPath, OpenMode.Read)
            let content = StringReader(file).readToEnd()
            
            println("Loading environment variables from ${path}...")

            let reader = TextReader(content)

            while (reader.readable()) {
                if (reader.peek() == r'#') { // 跳过注释
                    reader.skipUntil(r'\n', skipTarget: true)
                    continue
                }
                let key = reader.readUntil(r'=', mode: ReadUntilMode.Skip).trimAscii()
                if (!reader.readable()) {
                    break
                }
                reader.skipWhitespace()
                if (!reader.readable()) {
                    break
                }
                if (reader.peek() == r'\n') {
                    reader.skip()
                    continue
                }
                var value = if (reader.peek() == r'"') {
                    let builder = StringBuilder()
                    reader.skip()
                    if (!reader.readable()) {
                        break
                    }   
                    var foundQuote = false
                    while(reader.readable()) {
                        let rune = reader.read()
                        if (rune == r'"') {
                            foundQuote = true
                            break
                        }
                        builder.append(rune)
                        // 不确定是否要支持转义字符
                        /*if (rune != r'\\') {
                            builder.append(rune)
                            continue
                        }
                        if (reader.peek() == r'"') {
                            reader.skip()
                            builder.append('"')
                            continue
                        }
                        builder.append('\\')*/
                    }
                    if (reader.readable()) {
                        reader.skipUntil(r'\n', skipTarget: true)
                    }
                    if (!foundQuote) {
                        continue
                    }
                    builder.toString()
                } else {
                    let result = reader.readUntil(r'\n', mode: ReadUntilMode.Skip)
                    let commentIndex = result.indexOf('#')
                    match (commentIndex) {
                        case Some(index) => 
                            result[..index]
                        case None => result
                    }
                }

                value = value.trimAscii()

                if (value.contains('$')) {
                    for ((varKey, varVal) in getVariables()) {
                        if (value.contains('\$${varKey}')) {
                            value = value.replace('\$${varKey}', varVal)
                        }
                        if (value.contains('\${${varKey}}')) {
                            value = value.replace('\${${varKey}}', varVal)
                        }
                        if (!value.contains('$')) { // 快速跳出
                            break
                        }
                    }
                }

                setVariable(key, value)
                loaded[key] = value
            }
            
            println("Environment variables loaded successfully!")
            
            file.close()
        } catch (e: Exception) {
            println("Warning: .env file not found at ${path} or error loading .env file: ${e}")
        }

        return loaded
    }
}