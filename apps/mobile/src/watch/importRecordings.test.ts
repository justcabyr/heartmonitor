import { SessionRecording } from '../domain/sessionRecording';

import { importInbox, InboxFile } from './importRecordings';

const settings = {
  targetBPM: 150,
  warningFraction: 0.9,
  warningCooldown: 60,
  thresholdCooldown: 30,
  hysteresisBPM: 5,
  staleTimeout: 10,
  batteryGuardLevel: 0.1,
  saveToHealth: false,
};

const recording = (id = '6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31') => ({
  schemaVersion: 1,
  id,
  sourcePlatform: 'watchos',
  deviceModel: 'Watch7,1',
  watchAppVersion: '1.0.0',
  startedAt: '2026-10-06T02:00:00.000Z',
  settings,
  samples: [{ offset: 0, bpm: 72 }],
  events: [{ offset: 30, kind: 'warning' }],
  summary: {
    id,
    startedAt: '2026-10-06T02:00:00.000Z',
    endedAt: '2026-10-06T02:30:00.000Z',
    activeSeconds: 1800,
    sampleCount: 1,
    avgBPM: 72,
    minBPM: 72,
    maxBPM: 72,
    warningEvents: 1,
    thresholdEvents: 0,
    secondsAboveWarning: 0,
    secondsAboveTarget: 0,
    gapSeconds: 0,
    endReason: 'user',
  },
});

const fileFor = (value: unknown, name = 'session-6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31.json'): InboxFile => ({
  name,
  json: JSON.stringify(value),
});

describe('importInbox', () => {
  test('saves the original JSON and removes the inbox file', async () => {
    const raw = JSON.stringify(recording());
    const saved = new Map<string, string>();
    const removed: string[] = [];
    const imported = await importInbox(
      [{ name: 'session-6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31.json', json: raw }],
      async (session, bytes) => {
        saved.set(session.id, bytes);
      },
      async (name) => {
        removed.push(name);
      },
    );
    expect(imported).toHaveLength(1);
    expect(saved.get(recording().id)).toBe(raw);
    expect(removed).toEqual(['session-6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31.json']);
  });

  test('overwrites the same id when the file is imported again', async () => {
    const first = fileFor(recording());
    const secondValue = recording();
    secondValue.samples = [{ offset: 0, bpm: 80 }];
    secondValue.summary.avgBPM = 80;
    secondValue.summary.minBPM = 80;
    secondValue.summary.maxBPM = 80;
    const second = fileFor(secondValue);
    const saved = new Map<string, SessionRecording>();
    const save = async (session: SessionRecording) => {
      saved.set(session.id, session);
    };
    await importInbox([first], save, async () => undefined);
    await importInbox([second], save, async () => undefined);
    expect(saved.size).toBe(1);
    expect(saved.get(recording().id)?.summary.avgBPM).toBe(80);
  });

  test('leaves an invalid file in the inbox and still imports the valid one', async () => {
    const valid = fileFor(recording());
    const invalid = fileFor(
      { schemaVersion: 1 },
      'session-11111111-1111-4111-8111-111111111111.json',
    );
    const removed: string[] = [];
    await expect(
      importInbox(
        [invalid, valid],
        async () => undefined,
        async (name) => {
          removed.push(name);
        },
      ),
    ).rejects.toThrow(/session-11111111-1111-4111-8111-111111111111.json/);
    expect(removed).toEqual(['session-6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31.json']);
  });

  test.each([
    ['summary id', (value: ReturnType<typeof recording>) => {
      value.summary.id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    }],
    ['sample count', (value: ReturnType<typeof recording>) => {
      value.summary.sampleCount = 2;
    }],
    ['started at', (value: ReturnType<typeof recording>) => {
      value.summary.startedAt = '2026-10-06T03:00:00.000Z';
    }],
  ])('does not remove a file whose %s does not match', async (_label, mutate) => {
    const value = recording();
    mutate(value);
    const removed: string[] = [];
    await expect(
      importInbox([fileFor(value)], async () => undefined, async (name) => {
        removed.push(name);
      }),
    ).rejects.toThrow(/left in the inbox/);
    expect(removed).toEqual([]);
  });
});
