import { parseHeartRateSettings, warningBPM } from './heartRateSettings';
import { parseSessionRecording } from './sessionRecording';

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

const recording = () => ({
  schemaVersion: 1,
  id: '6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31',
  sourcePlatform: 'watchos',
  deviceModel: 'Watch7,1',
  watchAppVersion: '1.0.0',
  startedAt: '2026-10-06T02:00:00.000Z',
  settings,
  samples: [{ offset: 0, bpm: 72 }],
  events: [{ offset: 30, kind: 'warning' }],
  summary: {
    id: '6f1b1c3e-8a2d-4e5b-9c11-2d4a6b8e0f31',
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

describe('heart rate settings', () => {
  test('accepts a settings object inside the UX ranges', () => {
    const parsed = parseHeartRateSettings(settings);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(warningBPM(parsed.data)).toBe(135);
    }
  });

  test.each([
    ['targetBPM', 59],
    ['targetBPM', 231],
    ['warningFraction', 0.49],
    ['warningFraction', 1],
    ['warningCooldown', 4],
    ['warningCooldown', 601],
    ['thresholdCooldown', 4],
    ['thresholdCooldown', 601],
    ['hysteresisBPM', 0],
    ['hysteresisBPM', 21],
    ['staleTimeout', 0],
    ['staleTimeout', 121],
    ['batteryGuardLevel', 0.04],
    ['batteryGuardLevel', 0.31],
  ])('rejects %s = %s', (field, value) => {
    const parsed = parseHeartRateSettings({ ...settings, [field]: value });
    expect(parsed.success).toBe(false);
  });

  test('rejects an unknown field', () => {
    expect(parseHeartRateSettings({ ...settings, zone: 'threshold' }).success).toBe(false);
  });
});

describe('session recording', () => {
  test('accepts schema version 1', () => {
    const parsed = parseSessionRecording(recording());
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.id).toBe(parsed.data.summary.id);
    }
  });

  test('rejects a different schema version', () => {
    expect(parseSessionRecording({ ...recording(), schemaVersion: 2 }).success).toBe(false);
  });

  test('rejects an unknown end reason', () => {
    const value = recording();
    value.summary.endReason = 'crash';
    expect(parseSessionRecording(value).success).toBe(false);
  });

  test('rejects an unknown event kind', () => {
    const value = recording();
    value.events[0].kind = 'explode';
    expect(parseSessionRecording(value).success).toBe(false);
  });

  test('rejects a non-uuid id', () => {
    expect(parseSessionRecording({ ...recording(), id: 'session-1' }).success).toBe(false);
  });
});
