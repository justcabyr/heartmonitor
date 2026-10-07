import { SessionEvent } from '../domain/sessionRecording';

import { spansAreSeparated } from './aggregate';
import { dataBucketSegments, splitSamplesAtBreaks } from './chartSegments';

const events = (...kinds: SessionEvent[]): SessionEvent[] => kinds;

describe('spansAreSeparated', () => {
  test('a span of exactly 60 seconds is not a break', () => {
    expect(spansAreSeparated(0, 60, [], 60)).toBe(false);
  });

  test('a span longer than 60 seconds is a break', () => {
    expect(spansAreSeparated(0, 61, [], 61)).toBe(true);
  });

  test('a pause between samples is a break', () => {
    const pauses = events(
      { offset: 5, kind: 'paused' },
      { offset: 15, kind: 'resumed' },
    );
    expect(spansAreSeparated(0, 20, pauses, 20)).toBe(true);
  });
});

describe('chart segments', () => {
  test('splits drawn samples where the full recording has a gap', () => {
    const source = [
      { offset: 0, bpm: 70 },
      { offset: 61, bpm: 80 },
      { offset: 70, bpm: 82 },
    ];
    const segments = splitSamplesAtBreaks(
      [
        { offset: 0, bpm: 70 },
        { offset: 70, bpm: 82 },
      ],
      source,
      [],
      70,
    );
    expect(segments).toEqual([
      [{ offset: 0, bpm: 70 }],
      [{ offset: 70, bpm: 82 }],
    ]);
  });

  test('keeps buckets together until a gap or pause bucket', () => {
    const segments = dataBucketSegments([
      { start: 0, avg: 70, min: 70, max: 70, count: 1 },
      { start: 60, avg: 72, min: 71, max: 73, count: 2 },
      { start: 120, gap: true },
      { start: 180, avg: 90, min: 90, max: 90, count: 1 },
      { start: 240, paused: true },
      { start: 300, avg: 88, min: 88, max: 88, count: 1 },
    ]);
    expect(segments.map((segment) => segment.map((bucket) => bucket.start))).toEqual([
      [0, 60],
      [180],
      [300],
    ]);
  });
});
