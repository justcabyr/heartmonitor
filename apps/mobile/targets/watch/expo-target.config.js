/** @type {import('@bacons/apple-targets/app.plugin').Config & { infoPlist: Record<string, unknown> }} */
module.exports = {
  type: 'watch',
  name: 'watch',
  displayName: 'HeartThreshold',
  bundleIdentifier: '.watchkitapp',
  deploymentTarget: '10.0',
  frameworks: ['HealthKit'],
  entitlements: {
    'com.apple.developer.healthkit': true,
  },
  infoPlist: {
    NSHealthShareUsageDescription:
      'Heart rate is read to provide user-configured wellness alerts and session recordings.',
    NSHealthUpdateUsageDescription:
      'A workout is saved to Apple Health only when you turn that option on. The app recording is kept either way.',
    WKBackgroundModes: ['workout-processing'],
  },
};
