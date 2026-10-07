import { Platform } from 'react-native';

import { MockWatchBridge } from './MockWatchBridge';
import { WatchBridge } from './WatchBridge';

let bridge: WatchBridge | null = null;

export const getWatchBridge = (): WatchBridge => {
  if (bridge) {
    return bridge;
  }
  if (Platform.OS === 'ios') {
    const { AppleWatchBridge } = require('./AppleWatchBridge') as typeof import('./AppleWatchBridge');
    bridge = new AppleWatchBridge();
    return bridge;
  }
  bridge = new MockWatchBridge();
  return bridge;
};
