import path from 'path';

export const contractsPath = (...parts: string[]): string =>
  path.join(__dirname, '../../../../contracts', ...parts);
