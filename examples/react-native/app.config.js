// Expo reads app.json first and passes it here as `config`.
//
// The committed iOS bundle identifier is registered to Mentra's Apple
// Developer team, and Apple App IDs are globally unique. Automatic signing
// for a physical-device build therefore fails for any other team. Set
// MENTRA_IOS_BUNDLE_ID to your own reverse-DNS identifier before prebuild:
//
//   MENTRA_IOS_BUNDLE_ID=com.yourname.mentrasdkrn bunx expo prebuild --clean --platform ios
//
// Leaving the variable unset keeps the committed identifier so Mentra's
// TestFlight and CI builds are unaffected.
module.exports = ({ config }) => {
  const bundleIdentifier = (process.env.MENTRA_IOS_BUNDLE_ID || "").trim();
  if (!bundleIdentifier) {
    return config;
  }
  return {
    ...config,
    ios: {
      ...config.ios,
      bundleIdentifier,
    },
  };
};
