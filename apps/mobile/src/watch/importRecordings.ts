import { parseSessionRecording, SessionRecording } from '../domain/sessionRecording';

export type InboxFile = {
  name: string;
  json: string;
};

export const importInbox = async (
  files: InboxFile[],
  save: (recording: SessionRecording, raw: string) => Promise<void>,
  remove: (name: string) => Promise<void>,
): Promise<SessionRecording[]> => {
  const imported: SessionRecording[] = [];
  const invalid: string[] = [];

  for (const file of files) {
    const recording = validateRecording(file.json);
    if (!recording) {
      invalid.push(file.name);
      continue;
    }
    await save(recording, file.json);
    await remove(file.name);
    imported.push(recording);
  }

  if (invalid.length > 0) {
    throw new Error(
      `Could not import ${invalid.join(', ')}. Those files were left in the inbox.`,
    );
  }
  return imported;
};

const validateRecording = (raw: string): SessionRecording | null => {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  const parsed = parseSessionRecording(value);
  if (!parsed.success) {
    return null;
  }
  const recording = parsed.data;
  if (recording.summary.id !== recording.id) {
    return null;
  }
  if (recording.summary.sampleCount !== recording.samples.length) {
    return null;
  }
  if (recording.summary.startedAt !== recording.startedAt) {
    return null;
  }
  return recording;
};
