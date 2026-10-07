import { SessionRecording } from '../domain/sessionRecording';

import { WatchBridge, WatchStatus } from './WatchBridge';

const disconnected: WatchStatus = {
  platform: 'watchos',
  paired: false,
  appInstalled: false,
  reachable: false,
};

export class MockWatchBridge implements WatchBridge {
  readonly platform = 'watchos' as const;

  private readonly statusListeners = new Set<(status: WatchStatus) => void>();

  private readonly recordingListeners = new Set<() => void>();

  async isSupported(): Promise<boolean> {
    return false;
  }

  async getStatus(): Promise<WatchStatus> {
    return disconnected;
  }

  onStatusChange(cb: (status: WatchStatus) => void): () => void {
    this.statusListeners.add(cb);
    return () => {
      this.statusListeners.delete(cb);
    };
  }

  async importPendingRecordings(): Promise<SessionRecording[]> {
    return [];
  }

  onRecordingReceived(cb: () => void): () => void {
    this.recordingListeners.add(cb);
    return () => {
      this.recordingListeners.delete(cb);
    };
  }
}
