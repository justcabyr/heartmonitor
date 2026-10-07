import fs from 'fs';

import { SessionEvent } from '../domain/sessionRecording';
import { contractsPath } from '../test/contractsPath';
import { syntheticSamples } from '../test/syntheticSession';

import { aggregate, AggregateBucket } from './aggregate';

type VectorSample = { t: number; bpm: number };
type VectorEvent = { t: number; kind: SessionEvent['kind'] };
type ExpectedBucket = {
  start: number;
  avg?: number;
  min?: number;
  max?: number;
  count?: number;
  gap?: boolean;
  paused?: boolean;
};
type Synthetic = {
  durationSeconds: number;
  sampleEverySeconds: number;
  baseBPM: number;
  bpmModulus: number;
};
type ExpectedSummary = {
  bucketCount: number;
  gapBuckets: number;
  pausedBuckets: number;
  first: ExpectedBucket;
  last: ExpectedBucket;
};
type AggregationVector = {
  name: string;
  intervalSeconds: number;
  samples?: VectorSample[];
  events?: VectorEvent[];
  synthetic?: Synthetic;
  expected?: ExpectedBucket[];
  expectedSummary?: ExpectedSummary;
  summary: { endOffset: number };
};

const vectors = JSON.parse(
  fs.readFileSync(contractsPath('aggregation-test-vectors.json'), 'utf8'),
) as AggregationVector[];

const expectBucket = (actual: AggregateBucket, expected: ExpectedBucket) => {
  expect(actual.start).toBe(expected.start);
  if (expected.gap) {
    expect(actual.gap).toBe(true);
    expect(actual.paused).toBeUndefined();
    expect(actual.avg).toBeUndefined();
    return;
  }
  if (expected.paused) {
    expect(actual.paused).toBe(true);
    expect(actual.gap).toBeUndefined();
    expect(actual.avg).toBeUndefined();
    return;
  }
  expect(actual.avg).toBeCloseTo(expected.avg ?? 0, 6);
  expect(actual.min).toBeCloseTo(expected.min ?? 0, 6);
  expect(actual.max).toBeCloseTo(expected.max ?? 0, 6);
  expect(actual.count).toBe(expected.count);
};

describe('aggregate', () => {
  test('loads every aggregation vector', () => {
    expect(vectors.length).toBeGreaterThan(0);
    expect(vectors.map((vector) => vector.name)).toEqual(
      expect.arrayContaining([
        '1-minute buckets with a gap and a pause',
        'bucket avg min max and count',
        'empty buckets inside a span over 60 seconds are gaps',
        'a span of exactly 60 seconds is not a gap',
        'pauses are breaks and are not counted as gaps',
        '10-hour synthetic session',
      ]),
    );
  });

  test.each(vectors.map((vector) => [vector.name, vector] as const))(
    '%s',
    (_name, vector) => {
      const samples = vector.synthetic
        ? syntheticSamples(vector.synthetic)
        : (vector.samples ?? []).map((sample) => ({
          offset: sample.t,
          bpm: sample.bpm,
        }));
      const events: SessionEvent[] = (vector.events ?? []).map((event) => ({
        offset: event.t,
        kind: event.kind,
      }));
      const started = Date.now();
      const buckets = aggregate(samples, events, vector.intervalSeconds, vector.summary.endOffset);
      if (vector.synthetic) {
        expect(Date.now() - started).toBeLessThan(1000);
        const summary = vector.expectedSummary;
        expect(summary).toBeDefined();
        if (!summary) return;
        expect(buckets).toHaveLength(summary.bucketCount);
        expect(buckets.filter((bucket) => bucket.gap).length).toBe(summary.gapBuckets);
        expect(buckets.filter((bucket) => bucket.paused).length).toBe(summary.pausedBuckets);
        expectBucket(buckets[0], summary.first);
        expectBucket(buckets[buckets.length - 1], summary.last);
        return;
      }
      expect(vector.expected).toBeDefined();
      const expected = vector.expected ?? [];
      expect(buckets).toHaveLength(expected.length);
      expected.forEach((bucket, index) => {
        expectBucket(buckets[index], bucket);
      });
    },
  );
});
