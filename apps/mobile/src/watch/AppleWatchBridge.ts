import { EventSubscription, requireNativeModule } from 'expo-modules-core';

import { SessionRecording } from '../domain/sessionRecording';
import { saveRecording } from '../storage/sessionRepository';

import { importInbox, InboxFile } from './importRecordings';
import { WatchBridge, WatchStatus } from './WatchBridge';

type NativeInboxFile = {
  name: string;
  json: string;
};

type NativeWatchBridge = {
  isSupported(): Promise<boolean>;
  getStatus(): Promise<WatchStatus>;
  readInbox(): Promise<NativeInboxFile[]>;
  removeInboxFile(name: string): Promise<void>;
  takeLastError(): Promise<string | null>;
  addListener(eventName: 'onRecordingReceived', listener: () => void): EventSubscription;
  addListener(
    eventName: 'onStatusChange',
    listener: (status: WatchStatus) => void,
  ): EventSubscription;
};

const nativeBridge = (): NativeWatchBridge => requireNativeModule<NativeWatchBridge>('WatchBridge');

const errorMessage = (error: unknown): string => {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return 'The recording could not be imported.';
};

const asStatus = (value: WatchStatus): WatchStatus => {
  if (
    value?.platform !== 'watchos'
    || typeof value.paired !== 'boolean'
    || typeof value.appInstalled !== 'boolean'
    || typeof value.reachable !== 'boolean'
  ) {
    throw new Error('The watch status could not be read.');
  }
  return {
    platform: 'watchos',
    paired: value.paired,
    appInstalled: value.appInstalled,
    reachable: value.reachable,
  };
};

const asInbox = (files: NativeInboxFile[]): InboxFile[] => files.map((file) => {
  if (typeof file?.name !== 'string' || typeof file.json !== 'string') {
    throw new Error('The inbox returned a recording that could not be read.');
  }
  return { name: file.name, json: file.json };
});

export class AppleWatchBridge implements WatchBridge {
  readonly platform = 'watchos' as const;

  private readonly native = nativeBridge();

  async isSupported(): Promise<boolean> {
    return this.native.isSupported();
  }

  async getStatus(): Promise<WatchStatus> {
    return asStatus(await this.native.getStatus());
  }

  onStatusChange(cb: (status: WatchStatus) => void): () => void {
    const subscription = this.native.addListener('onStatusChange', (status) => {
      cb(asStatus(status));
    });
    return () => {
      subscription.remove();
    };
  }

  async importPendingRecordings(): Promise<SessionRecording[]> {
    const files = asInbox(await this.native.readInbox());
    let imported: SessionRecording[] = [];
    let importFailure: unknown;
    try {
      imported = await importInbox(
        files,
        saveRecording,
        (name) => this.native.removeInboxFile(name),
      );
    } catch (error) {
      importFailure = error;
    }
    const receiveError = await this.native.takeLastError();
    if (importFailure && receiveError) {
      throw new Error(`${errorMessage(importFailure)} ${receiveError}`);
    }
    if (importFailure) {
      throw importFailure instanceof Error
        ? importFailure
        : new Error(errorMessage(importFailure));
    }
    if (receiveError) {
      throw new Error(receiveError);
    }
    return imported;
  }

  onRecordingReceived(cb: () => void): () => void {
    const subscription = this.native.addListener('onRecordingReceived', cb);
    return () => {
      subscription.remove();
    };
  }
}
