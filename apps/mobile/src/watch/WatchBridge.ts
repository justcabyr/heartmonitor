import { HeartRateSettings } from '../domain/heartRateSettings';
import { SessionRecording } from '../domain/sessionRecording';

export type WatchPlatform = 'watchos' | 'wearos' | 'garmin';

export interface WatchStatus {
  platform: WatchPlatform;
  paired: boolean;
  appInstalled: boolean;
  reachable: boolean;
}

export interface WatchBridge {
  platform: WatchPlatform;
  isSupported(): Promise<boolean>;
  getStatus(): Promise<WatchStatus>;
  onStatusChange(cb: (status: WatchStatus) => void): () => void;
  importPendingRecordings(): Promise<SessionRecording[]>;
  onRecordingReceived(cb: () => void): () => void;
  pushSettings?(settings: HeartRateSettings): Promise<'sent' | 'queued' | 'unavailable'>;
}
