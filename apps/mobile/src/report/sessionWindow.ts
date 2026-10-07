import { SessionRecording } from '../domain/sessionRecording';

export const sessionEndOffset = (recording: SessionRecording): number => {
  const start = Date.parse(recording.startedAt);
  const end = Date.parse(recording.summary.endedAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) {
    throw new Error('The recording dates could not be read.');
  }
  return (end - start) / 1000;
};
