import { WatchBridge } from './WatchBridge';

type ImportListener = (error: string | null) => void;

const listeners = new Set<ImportListener>();
let tail: Promise<void> = Promise.resolve();

export const subscribeImports = (listener: ImportListener): (() => void) => {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
};

const notify = (error: string | null) => {
  for (const listener of listeners) {
    listener(error);
  }
};

const messageFrom = (error: unknown): string => {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return 'The recording could not be imported.';
};

export const requestImport = (bridge: WatchBridge): Promise<void> => {
  const run = tail.then(async () => {
    try {
      await bridge.importPendingRecordings();
      notify(null);
    } catch (error) {
      notify(messageFrom(error));
    }
  });
  tail = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
};

export const watchForRecordings = (bridge: WatchBridge): (() => void) => {
  const unsubscribe = bridge.onRecordingReceived(() => {
    void requestImport(bridge);
  });
  void requestImport(bridge);
  return unsubscribe;
};
