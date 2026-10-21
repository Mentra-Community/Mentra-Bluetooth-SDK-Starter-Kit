#!/usr/bin/env node
// Runs after `bun install` in the React Native examples. When
// MENTRA_BLUETOOTH_SDK_PACKAGE_PATH points at a MentraOS checkout's
// mobile/modules/bluetooth-sdk, replaces each installed @mentra/* package that
// the checkout's mobile workspace provides with a copy of its source, so Metro,
// TypeScript, config plugins, and native autolinking build that source while
// resolving dependencies from this app exactly as for the published packages.
// Install the MentraOS mobile workspace first (`bun install` in mobile/) so the
// packages are built. Does nothing when the variable is unset.
import fs from "node:fs"
import path from "node:path"

const sdkPath = process.env.MENTRA_BLUETOOTH_SDK_PACKAGE_PATH?.trim()
if (!sdkPath) process.exit(0)

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
sources.set("@mentra/bluetooth-sdk", path.resolve(sdkPath))

// Skip installed dependencies and local native build output.
const skip = (file) => /(^|\/)(node_modules|\.gradle|\.cxx)$|\/android(\/[^/]+)?\/build$/.test(file)

const scope = path.resolve("node_modules/@mentra")
for (const name of fs.readdirSync(scope)) {
  const source = sources.get(`@mentra/${name}`)
  if (!source) continue
  fs.rmSync(path.join(scope, name), {recursive: true, force: true})
  fs.cpSync(source, path.join(scope, name), {recursive: true, filter: (file) => !skip(file)})
  console.log(`Installed @mentra/${name} from ${source}`)
}
