// The MentraOS Bluetooth SDK source the examples build against, or null for the
// published packages. MENTRA_BLUETOOTH_SDK_PUBLISHED=1 forces the published
// packages; otherwise MENTRA_BLUETOOTH_SDK_PACKAGE_PATH wins; otherwise the
// MentraOS mobile workspace next to this repository (../mentraos/mobile) is used
// when present. The examples take every @mentra/* package that workspace
// provides (the SDK, engine, and siblings) from it; see install-mentraos-sources.mjs.
const fs = require("fs")
const path = require("path")

module.exports = function mentraosSdkPath() {
  if (process.env.MENTRA_BLUETOOTH_SDK_PUBLISHED === "1") return null
  const explicit = process.env.MENTRA_BLUETOOTH_SDK_PACKAGE_PATH?.trim()
  if (explicit) return path.resolve(explicit)
  const mobile = path.resolve(__dirname, "../../mentraos/mobile")
  const sdk = path.join(mobile, "modules/bluetooth-sdk")
  return fs.existsSync(path.join(mobile, "package.json")) && fs.existsSync(path.join(sdk, "package.json")) ? sdk : null
}
