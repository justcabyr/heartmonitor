const fs = require('fs');
const path = require('path');

const { withDangerousMod, withFinalizedMod } = require('expo/config-plugins');
const plistModule = require('@expo/plist');
const plist = plistModule.default ?? plistModule;

const targetConfigPath = path.join(__dirname, '../targets/watch/expo-target.config.js');
const packageRelativePath = '../../../packages/threshold-engine-swift';
const packageProductName = 'ThresholdEngine';
const localPackageId = 'A1C0FFEE571E5701D0000001';
const productDependencyId = 'A1C0FFEE571E5701D0000002';
const buildFileId = 'A1C0FFEE571E5701D0000003';

const readTargetInfoPlist = () => {
  const targetConfig = require(targetConfigPath);
  return targetConfig.infoPlist ?? {};
};

const withWatchInfoPlist = (config) =>
  withDangerousMod(config, [
    'ios',
    (modConfig) => {
      const plistPath = path.join(
        modConfig.modRequest.projectRoot,
        'targets/watch/Info.plist',
      );
      const current = fs.existsSync(plistPath)
        ? plist.parse(fs.readFileSync(plistPath, 'utf8'))
        : {};
      const next = {
        ...current,
        ...readTargetInfoPlist(),
      };
      fs.mkdirSync(path.dirname(plistPath), { recursive: true });
      fs.writeFileSync(plistPath, plist.build(next));
      return modConfig;
    },
  ]);

const insertAfter = (source, marker, insertion) => {
  if (source.includes(insertion.trim())) {
    return source;
  }
  const index = source.indexOf(marker);
  if (index === -1) {
    throw new Error(`Could not find ${marker} while linking ${packageProductName}`);
  }
  return source.slice(0, index + marker.length) + insertion + source.slice(index + marker.length);
};

const linkThresholdEngine = (project) => {
  if (project.includes(`productName = ${packageProductName};`)) {
    return project;
  }

  const watchTarget = project.match(
    /\t\t[A-Z0-9]{24} \/\* watch \*\/ = \{\n\t\t\tisa = PBXNativeTarget;[\s\S]*?\n\t\t\};/,
  );
  if (!watchTarget) {
    throw new Error('Could not find the watch native target');
  }

  const frameworksPhaseId = watchTarget[0].match(
    /([A-Z0-9]{24}) \/\* Frameworks \*\//,
  )?.[1];
  if (!frameworksPhaseId) {
    throw new Error('Could not find the watch Frameworks build phase');
  }

  let next = watchTarget[0];
  if (next.includes('packageProductDependencies')) {
    next = next.replace(
      'packageProductDependencies = (',
      `packageProductDependencies = (\n\t\t\t\t${productDependencyId} /* ${packageProductName} */,`,
    );
  } else {
    next = next.replace(
      'name = watch;',
      `name = watch;\n\t\t\tpackageProductDependencies = (\n\t\t\t\t${productDependencyId} /* ${packageProductName} */,\n\t\t\t);`,
    );
  }
  project = project.replace(watchTarget[0], next);

  const frameworksPhase = project.match(
    new RegExp(
      `\\t\\t${frameworksPhaseId} /\\* Frameworks \\*/ = \\{\\n\\t\\t\\tisa = PBXFrameworksBuildPhase;[\\s\\S]*?\\n\\t\\t\\};`,
    ),
  );
  if (!frameworksPhase) {
    throw new Error('Could not find the watch Frameworks phase block');
  }
  project = project.replace(
    frameworksPhase[0],
    frameworksPhase[0].replace(
      'files = (',
      `files = (\n\t\t\t\t${buildFileId} /* ${packageProductName} in Frameworks */,`,
    ),
  );

  project = insertAfter(
    project,
    '/* Begin PBXBuildFile section */\n',
    `\t\t${buildFileId} /* ${packageProductName} in Frameworks */ = {isa = PBXBuildFile; productRef = ${productDependencyId} /* ${packageProductName} */; };\n`,
  );

  const projectSection = project.match(
    /\t\t[A-F0-9]{24} \/\* Project object \*\/ = \{\n\t\t\tisa = PBXProject;[\s\S]*?\n\t\t\};/,
  );
  if (!projectSection) {
    throw new Error('Could not find the Xcode project object');
  }
  let projectObject = projectSection[0];
  if (projectObject.includes('packageReferences = (')) {
    projectObject = projectObject.replace(
      'packageReferences = (',
      `packageReferences = (\n\t\t\t\t${localPackageId} /* XCLocalSwiftPackageReference "threshold-engine-swift" */,`,
    );
  } else {
    projectObject = projectObject.replace(
      'mainGroup = ',
      `packageReferences = (\n\t\t\t\t${localPackageId} /* XCLocalSwiftPackageReference "threshold-engine-swift" */,\n\t\t\t);\n\t\t\tmainGroup = `,
    );
  }
  project = project.replace(projectSection[0], projectObject);

  const localSection = `/* Begin XCLocalSwiftPackageReference section */
		${localPackageId} /* XCLocalSwiftPackageReference "threshold-engine-swift" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = "${packageRelativePath}";
		};
/* End XCLocalSwiftPackageReference section */

`;
  const productSection = `/* Begin XCSwiftPackageProductDependency section */
		${productDependencyId} /* ${packageProductName} */ = {
			isa = XCSwiftPackageProductDependency;
			package = ${localPackageId} /* XCLocalSwiftPackageReference "threshold-engine-swift" */;
			productName = ${packageProductName};
		};
/* End XCSwiftPackageProductDependency section */

`;

  if (!project.includes('XCLocalSwiftPackageReference section')) {
    project = insertAfter(project, 'objects = {\n', `${localSection}${productSection}`);
  }

  return project;
};

const withThresholdEnginePackage = (config) =>
  withFinalizedMod(config, [
    'ios',
    (modConfig) => {
      const iosRoot = modConfig.modRequest.platformProjectRoot;
      const projects = fs
        .readdirSync(iosRoot)
        .filter((entry) => entry.endsWith('.xcodeproj'));
      if (projects.length !== 1) {
        throw new Error(`Expected one Xcode project in ${iosRoot}`);
      }
      const projectPath = path.join(iosRoot, projects[0], 'project.pbxproj');
      const project = fs.readFileSync(projectPath, 'utf8');
      fs.writeFileSync(projectPath, linkThresholdEngine(project));
      return modConfig;
    },
  ]);

module.exports = (config) => withThresholdEnginePackage(withWatchInfoPlist(config));
