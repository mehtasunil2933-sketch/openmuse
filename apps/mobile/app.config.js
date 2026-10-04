// Android/iOS launcher icon. The PNGs are kept as base64 text (assets/*.png.b64) and
// written next to them when Expo reads this config, e.g. during `expo prebuild`.
const fs = require("node:fs");
const path = require("node:path");

const ICON_BACKGROUND = "#F3E3C3";

function writeIcon(name) {
  const target = path.join(__dirname, "assets", name);
  const source = `${target}.b64`;
  if (!fs.existsSync(target) && fs.existsSync(source))
    fs.writeFileSync(target, Buffer.from(fs.readFileSync(source, "utf8"), "base64"));
  return `./assets/${name}`;
}

module.exports = ({ config }) => ({
  ...config,
  icon: writeIcon("icon.png"),
  android: {
    ...config.android,
    adaptiveIcon: {
      foregroundImage: writeIcon("adaptive-icon.png"),
      backgroundColor: ICON_BACKGROUND,
    },
  },
});
