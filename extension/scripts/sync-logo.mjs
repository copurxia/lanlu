import { readFileSync, mkdirSync, writeFileSync } from "node:fs"
import { dirname, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { Resvg } from "@resvg/resvg-js"

const __dirname = dirname(fileURLToPath(import.meta.url))
const extensionDir = resolve(__dirname, "..")
const sourceSvg = resolve(extensionDir, "../frontend/public/logo.svg")
const outputPng = resolve(extensionDir, "assets/icon.png")

const svg = readFileSync(sourceSvg, "utf-8")
const resvg = new Resvg(svg, {
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
