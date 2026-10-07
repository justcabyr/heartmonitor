const fs = require('fs');
const path = require('path');

const { withDangerousMod } = require('expo/config-plugins');

const windowStartup = `#if os(iOS) || os(tvOS)
    window = UIWindow(frame: UIScreen.main.bounds)
    factory.startReactNative(
      withModuleName: "main",
      in: window,
      launchOptions: launchOptions)
#endif

`;

const withIosSceneLifecycle = (config) =>
  withDangerousMod(config, [
    'ios',
    (modConfig) => {
      const appDelegatePath = path.join(
        modConfig.modRequest.platformProjectRoot,
        modConfig.modRequest.projectName,
        'AppDelegate.swift',
      );
      const source = fs.readFileSync(appDelegatePath, 'utf8');
      let next = source;
      if (!next.includes('ExpoReactNativeFactoryProvider')) {
        next = next.replace(
          'class AppDelegate: ExpoAppDelegate {',
          'class AppDelegate: ExpoAppDelegate, ExpoReactNativeFactoryProvider {',
        );
      }
      if (next.includes(windowStartup)) {
        next = next.replace(windowStartup, '');
      }
      if (next === source) {
        if (!next.includes('ExpoReactNativeFactoryProvider')) {
          throw new Error('Could not adopt ExpoReactNativeFactoryProvider in AppDelegate.swift');
        }
        return modConfig;
      }
      fs.writeFileSync(appDelegatePath, next);
      return modConfig;
    },
  ]);

module.exports = withIosSceneLifecycle;
