// Ad-hoc sign the app after electron-builder packaging.
// electron-builder skips signing entirely when no Developer ID
// certificate exists. This ensures the app gets at least ad-hoc
// signing so macOS doesn't reject it outright.
const { execSync } = require('child_process')
const path = require('path')

exports.default = async function (context) {
  const appPath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`)
  console.log(`[afterSign] Ad-hoc signing: ${appPath}`)
  try {
    execSync(`codesign --force --deep -s - "${appPath}"`, { stdio: 'inherit' })
    console.log('[afterSign] Ad-hoc signing completed successfully')
  } catch (e) {
    console.error('[afterSign] Ad-hoc signing failed:', e.message)
  }
}
