#!/usr/bin/env node
// Runs after `bun install` in the React Native examples. When building against
// a MentraOS checkout's mobile/modules/bluetooth-sdk (see mentraos-sdk-path.cjs),
// replaces each installed @mentra/* package that
// the checkout's mobile workspace provides with a copy of its source, so Metro,
// TypeScript, config plugins, and native autolinking build that source while
// resolving dependencies from this app exactly as for the published packages.
// Install the MentraOS mobile workspace first (`bun install` in mobile/) so the
// packages are built. Does nothing when building against published packages.
import fs from "node:fs"
import path from "node:path"

import mentraosSdkPath from "./mentraos-sdk-path.cjs"

const sdkPath = mentraosSdkPath()
if (!sdkPath) process.exit(0)
if (!fs.existsSync(path.join(sdkPath, "plugin/build"))) {
  console.error(`${sdkPath} is not built: run \`bun install\` in its MentraOS mobile/ directory, or set MENTRA_BLUETOOTH_SDK_PUBLISHED=1.`)
  process.exit(1)
}

const mobileRoot = path.resolve(sdkPath, "../..")
const {workspaces} = JSON.parse(fs.readFileSync(path.join(mobileRoot, "package.json"), "utf8"))
const sources = new Map()
for (const pattern of workspaces) {
  const dirs = pattern.endsWith("/*")
    ? fs.readdirSync(path.join(mobileRoot, pattern.slice(0, -2))).map((name) => path.join(mobileRoot, pattern.slice(0, -2), name))
    : [path.join(mobileRoot, pattern)]
  for (const dir of dirs) {
    const manifest = path.join(dir, "package.json")
    if (fs.existsSync(manifest)) sources.set(JSON.parse(fs.readFileSync(manifest, "utf8")).name, dir)
  }
}
sources.set("@mentra/bluetooth-sdk", sdkPath)

// Skip installed dependencies and native build output (any path separator).
const skip = (relative) => {
  const parts = relative.split(/[\\/]/)
  const name = parts.at(-1)
  return ["node_modules", ".gradle", ".cxx"].includes(name) || (name === "build" && parts.includes("android"))
}

const scope = path.resolve("node_modules/@mentra")
for (const name of fs.readdirSync(scope)) {
  const source = sources.get(`@mentra/${name}`)
  if (!source) continue
  fs.rmSync(path.join(scope, name), {recursive: true, force: true})
  fs.cpSync(source, path.join(scope, name), {recursive: true, filter: (file) => !skip(path.relative(source, file))})
  console.log(`Installed @mentra/${name} from ${source}`)
}
