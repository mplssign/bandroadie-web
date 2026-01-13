import packageJson from '../../package.json';

export function getAppVersion(): string {
  return packageJson.version;
}

export function getAppName(): string {
  return 'BandRoadie';
}

export function getVersionDisplay(): string {
  const version = getAppVersion();
  return `${version}-beta.1 (build)`;
}