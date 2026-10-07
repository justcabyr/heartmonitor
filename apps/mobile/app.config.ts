import { ConfigContext, ExpoConfig } from 'expo/config';

const shareUsage =
  'Heart rate is read to provide user-configured wellness alerts and session recordings.';
const updateUsage =
  'A workout is saved to Apple Health only when you turn that option on. The app recording is kept either way.';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'HeartThreshold',
  slug: 'heartthreshold',
  scheme: 'heartthreshold',
  version: '1.0.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  ios: {
    bundleIdentifier: 'com.justcabyr.heartthreshold',
    appleTeamId: 'G7F58Z7BUB',
    supportsTablet: false,
    infoPlist: {
      NSHealthShareUsageDescription: shareUsage,
      NSHealthUpdateUsageDescription: updateUsage,
      UIApplicationSceneManifest: {
        UIApplicationSupportsMultipleScenes: false,
        UISceneConfigurations: {
          UIWindowSceneSessionRoleApplication: [
            {
              UISceneConfigurationName: 'Default Configuration',
              UISceneDelegateClassName: 'EXExpoAppSceneDelegate',
            },
          ],
        },
      },
    },
  },
  plugins: [
    'expo-router',
    'expo-dev-client',
    'expo-status-bar',
    '@bacons/apple-targets',
    './plugins/withWatchTarget',
    './plugins/withIosSceneLifecycle',
    './plugins/withAutomaticSigning',
  ],
  experiments: {
    typedRoutes: false,
  },
});
