import { Directory, File, Paths } from 'expo-file-system';
import { openDatabaseAsync, SQLiteDatabase } from 'expo-sqlite';

import { endReasonSchema, parseSessionRecording, SessionRecording } from '../domain/sessionRecording';

export type SessionListItem = {
  id: string;
  startedAt: string;
  endedAt: string;
  activeSeconds: number;
  avgBPM: number;
  minBPM: number;
  maxBPM: number;
  warningEvents: number;
  thresholdEvents: number;
  secondsAboveWarning: number;
  secondsAboveTarget: number;
  gapSeconds: number;
  endReason: SessionRecording['summary']['endReason'];
  targetBPM: number;
  warningFraction: number;
  sampleCount: number;
};

type SessionRow = {
  id: string;
  started_at: string;
  ended_at: string;
  active_seconds: number;
  avg_bpm: number;
  min_bpm: number;
  max_bpm: number;
  warning_events: number;
  threshold_events: number;
  seconds_above_warning: number;
  seconds_above_target: number;
  gap_seconds: number;
  end_reason: string;
  target_bpm: number;
  warning_fraction: number;
  sample_count: number;
};

const sessionIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const assertSessionId = (id: string): string => {
  if (!sessionIdPattern.test(id)) {
    throw new Error('This session id is not valid.');
  }
  return id;
};

let opening: Promise<SQLiteDatabase> | null = null;

const database = (): Promise<SQLiteDatabase> => {
  if (!opening) {
    opening = openDatabaseAsync('heartthreshold.db')
      .then(async (db) => {
        await db.execAsync(`
        CREATE TABLE IF NOT EXISTS sessions (
          id TEXT PRIMARY KEY NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT NOT NULL,
          active_seconds REAL NOT NULL,
          avg_bpm REAL NOT NULL,
          min_bpm REAL NOT NULL,
          max_bpm REAL NOT NULL,
          warning_events INTEGER NOT NULL,
          threshold_events INTEGER NOT NULL,
          seconds_above_warning REAL NOT NULL,
          seconds_above_target REAL NOT NULL,
          gap_seconds REAL NOT NULL,
          end_reason TEXT NOT NULL,
          target_bpm REAL NOT NULL,
          warning_fraction REAL NOT NULL,
          sample_count INTEGER NOT NULL
        )
      `);
        return db;
      })
      .catch((error: unknown) => {
        opening = null;
        throw error;
      });
  }
  return opening;
};

const recordingsDirectory = (): Directory => {
  const directory = new Directory(Paths.document, 'recordings');
  if (!directory.exists) {
    directory.create({ intermediates: true, idempotent: true });
  }
  return directory;
};

const recordingFile = (id: string): File => new File(recordingsDirectory(), `${assertSessionId(id)}.json`);

const toListItem = (row: SessionRow): SessionListItem => {
  const endReason = endReasonSchema.safeParse(row.end_reason);
  if (!endReason.success) {
    throw new Error('A saved session could not be read.');
  }
  return {
    id: row.id,
    startedAt: row.started_at,
    endedAt: row.ended_at,
    activeSeconds: row.active_seconds,
    avgBPM: row.avg_bpm,
    minBPM: row.min_bpm,
    maxBPM: row.max_bpm,
    warningEvents: row.warning_events,
    thresholdEvents: row.threshold_events,
    secondsAboveWarning: row.seconds_above_warning,
    secondsAboveTarget: row.seconds_above_target,
    gapSeconds: row.gap_seconds,
    endReason: endReason.data,
    targetBPM: row.target_bpm,
    warningFraction: row.warning_fraction,
    sampleCount: row.sample_count,
  };
};

export const saveRecording = async (recording: SessionRecording, raw: string): Promise<void> => {
  const id = assertSessionId(recording.id);
  const file = recordingFile(id);
  file.write(raw);
  const db = await database();
  await db.runAsync(
    `INSERT OR REPLACE INTO sessions (
      id, started_at, ended_at, active_seconds, avg_bpm, min_bpm, max_bpm,
      warning_events, threshold_events, seconds_above_warning, seconds_above_target,
      gap_seconds, end_reason, target_bpm, warning_fraction, sample_count
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    id,
    recording.startedAt,
    recording.summary.endedAt,
    recording.summary.activeSeconds,
    recording.summary.avgBPM,
    recording.summary.minBPM,
    recording.summary.maxBPM,
    recording.summary.warningEvents,
    recording.summary.thresholdEvents,
    recording.summary.secondsAboveWarning,
    recording.summary.secondsAboveTarget,
    recording.summary.gapSeconds,
    recording.summary.endReason,
    recording.settings.targetBPM,
    recording.settings.warningFraction,
    recording.summary.sampleCount,
  );
};

export const listSessions = async (): Promise<SessionListItem[]> => {
  const db = await database();
  const rows = await db.getAllAsync<SessionRow>(
    'SELECT * FROM sessions ORDER BY started_at DESC',
  );
  return rows.map(toListItem);
};

export const loadRecording = async (id: string): Promise<SessionRecording> => {
  const sessionId = assertSessionId(id);
  const db = await database();
  const row = await db.getFirstAsync<SessionRow>('SELECT id FROM sessions WHERE id = ?', sessionId);
  if (!row) {
    throw new Error('This session is not on this iPhone.');
  }
  const file = recordingFile(sessionId);
  if (!file.exists) {
    throw new Error('The recording file is missing, so this report cannot be shown.');
  }
  const raw = await file.text();
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error('The recording file could not be read.');
  }
  const parsed = parseSessionRecording(value);
  if (!parsed.success || parsed.data.id !== sessionId) {
    throw new Error('The recording file could not be read.');
  }
  return parsed.data;
};
