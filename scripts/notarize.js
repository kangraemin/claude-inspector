const { execSync } = require("child_process");
const path = require("path");

exports.default = async function notarize(context) {
  if (context.electronPlatformName !== "darwin") return;

  const appleId = process.env.APPLE_ID;
  const password = process.env.APPLE_APP_SPECIFIC_PASSWORD;
  const teamId = process.env.APPLE_TEAM_ID;

  if (!appleId || !password || !teamId) {
    console.log("⚠ Skipping notarization: missing APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, or APPLE_TEAM_ID");
    return;
  }

  const appPath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`);
  const zipPath = path.join(context.appOutDir, "notarize-tmp.zip");

  console.log(`Notarizing ${appPath}...`);

  execSync(`ditto -c -k --keepParent "${appPath}" "${zipPath}"`);

  try {
    execSync(
      `xcrun notarytool submit "${zipPath}" --apple-id "${appleId}" --password "${password}" --team-id "${teamId}" --wait`,
      { stdio: "inherit", timeout: 600000 }
    );
    try {
      execSync(`xcrun stapler staple "${appPath}"`, { stdio: "inherit" });
    } catch {
      console.log("⚠ Staple failed (ticket may not have propagated yet) — notarization itself succeeded, continuing...");
    }
    console.log("Notarization complete!");
  } finally {
    try { require("fs").unlinkSync(zipPath); } catch {}
  }
};
