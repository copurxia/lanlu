import { readFileSync, mkdirSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { Resvg } from "@resvg/resvg-js"

const __dirname = dirname(fileURLToPath(import.meta.url))
const extensionDir = resolve(__dirname, "..")
const sourceSvg = resolve(extensionDir, "../frontend/public/logo.svg")
const outputPng = resolve(extensionDir, "assets/icon.png")

const rawSvg = readFileSync(sourceSvg, "utf-8")

// Resvg does not fully honor CSS variables in this logo, so we keep the
// geometry from source SVG but inline the expected light theme colors.
const normalizedSvg = rawSvg
  .replace(/<style[\s\S]*?<\/style>/i, "")
  .replace(/class=(['"])logo-bg\1/g, 'fill="#0f172a"')
  .replace(/class=(['"])logo-fg\1/g, 'fill="#ffffff"')

const resvg = new Resvg(normalizedSvg, {
  fitTo: {
    mode: "width",
    value: 128
  },
  background: "rgba(0,0,0,0)"
})

const png = resvg.render().asPng()
mkdirSync(resolve(extensionDir, "assets"), { recursive: true })
writeFileSync(outputPng, png)
console.log(`Synced icon from ${sourceSvg} -> ${outputPng}`)
