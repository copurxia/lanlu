import { promises as fs } from 'node:fs'
import path from 'node:path'
import { brotliCompress } from 'node:zlib'
import { promisify } from 'node:util'
import { constants as zlibConstants } from 'node:zlib'

const compress = promisify(brotliCompress)
const outputDir = path.resolve(process.cwd(), 'out')
const staticDir = path.join(outputDir, '_next', 'static')
const chunkDir = path.join(staticDir, 'chunks')

async function walk(dir) {
  const entries = await fs.readdir(dir, { withFileTypes: true })
  const files = []

  for (const entry of entries) {
    const entryPath = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      files.push(...await walk(entryPath))
      continue
    }
    if (entry.isFile()) {
      files.push(entryPath)
    }
  }

  return files
}

function shouldCompress(filePath) {
  if (filePath.endsWith('.br')) return false
  if (filePath.endsWith('.css')) return true
  return filePath.endsWith('.js') && filePath.startsWith(chunkDir + path.sep)
}

async function compressFile(filePath) {
  const source = await fs.readFile(filePath)
  const compressed = await compress(source, {
    params: {
      [zlibConstants.BROTLI_PARAM_QUALITY]: zlibConstants.BROTLI_MAX_QUALITY,
      [zlibConstants.BROTLI_PARAM_MODE]: zlibConstants.BROTLI_MODE_TEXT,
    },
  })

  await fs.writeFile(`${filePath}.br`, compressed)
  return { original: source.byteLength, compressed: compressed.byteLength }
}

async function main() {
  const staticStat = await fs.stat(staticDir).catch(() => null)
  if (!staticStat?.isDirectory()) {
    throw new Error(`Next export output not found: ${staticDir}`)
  }

  const files = (await walk(staticDir)).filter(shouldCompress)
  let totalOriginal = 0
  let totalCompressed = 0

  for (const filePath of files) {
    const { original, compressed } = await compressFile(filePath)
    totalOriginal += original
    totalCompressed += compressed
  }

  console.log(
    `[brotli] generated ${files.length} files, ${totalOriginal} -> ${totalCompressed} bytes`
  )
}

main().catch((error) => {
  console.error('[brotli] failed:', error)
  process.exitCode = 1
})
