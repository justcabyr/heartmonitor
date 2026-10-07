const { withXcodeProject } = require('expo/config-plugins');

const withAutomaticSigning = (config) =>
  withXcodeProject(config, (modConfig) => {
    const teamId = modConfig.ios?.appleTeamId;
    if (!teamId) {
      return modConfig;
    }

    const project = modConfig.modResults;
    const configurations = project.pbxXCBuildConfigurationSection();
    for (const configuration of Object.values(configurations)) {
      const settings = configuration.buildSettings;
      if (!settings?.PRODUCT_BUNDLE_IDENTIFIER) {
        continue;
      }
      settings.CODE_SIGN_STYLE = 'Automatic';
      settings.CODE_SIGN_IDENTITY = '"Apple Development"';
      const bundleId = String(settings.PRODUCT_BUNDLE_IDENTIFIER);
      const sdk = String(settings.SDKROOT ?? '');
      if (sdk === 'watchos' || bundleId.includes('watchkitapp')) {
        settings.SUPPORTED_PLATFORMS = '"watchos watchsimulator"';
      }
    }

    const nativeTargets = project.pbxNativeTargetSection();
    const projectSection = project.pbxProjectSection();
    for (const [targetId, target] of Object.entries(nativeTargets)) {
      if (typeof target !== 'object' || !target.productType) {
        continue;
      }
      for (const entry of Object.values(projectSection)) {
        if (typeof entry !== 'object' || !entry.attributes) {
          continue;
        }
        entry.attributes.TargetAttributes = entry.attributes.TargetAttributes ?? {};
        const attributes = entry.attributes.TargetAttributes[targetId] ?? {};
        attributes.ProvisioningStyle = 'Automatic';
        entry.attributes.TargetAttributes[targetId] = attributes;
      }
    }

    return modConfig;
  });

module.exports = withAutomaticSigning;
