import fs from 'fs';

import { contractsPath } from '../test/contractsPath';
import { syntheticSamples } from '../test/syntheticSession';

import { downsample, drawingPointLimit } from './downsample';

describe('downsample', () => {
  test('keeps every sample when the series is already small', () => {
    const samples = [
      { offset: 0, bpm: 70 },
      { offset: 5, bpm: 180 },
      { offset: 10, bpm: 90 },
    ];
    expect(downsample(samples)).toEqual(samples);
  });

  test('keeps real samples only, including the ends and the extrema', () => {
    const samples = Array.from({ length: 4000 }, (_, index) => ({
      offset: index,
      bpm: index === 2500 ? 10 : index === 2600 ? 220 : 80,
    }));
    const drawn = downsample(samples, 100);
    expect(drawn.length).toBeLessThanOrEqual(100);
    expect(drawn.length).toBeGreaterThanOrEqual(2);
    expect(drawn[0]).toEqual(samples[0]);
    expect(drawn[drawn.length - 1]).toEqual(samples[samples.length - 1]);
    const offsets = new Set(samples.map((sample) => sample.offset));
    for (const point of drawn) {
      expect(offsets.has(point.offset)).toBe(true);
      expect(samples.find((sample) => sample.offset === point.offset)?.bpm).toBe(point.bpm);
    }
    expect(drawn.some((point) => point.bpm === 10)).toBe(true);
    expect(drawn.some((point) => point.bpm === 220)).toBe(true);
  });

  test('draws a 10-hour series under the point limit', () => {
    const file = JSON.parse(
      fs.readFileSync(contractsPath('aggregation-test-vectors.json'), 'utf8'),
    ) as Array<{ name: string; synthetic?: Parameters<typeof syntheticSamples>[0] }>;
    const synthetic = file.find((vector) => vector.name === '10-hour synthetic session')?.synthetic;
    expect(synthetic).toBeDefined();
    if (!synthetic) return;
    const samples = syntheticSamples(synthetic);
    const started = Date.now();
    const drawn = downsample(samples);
    expect(Date.now() - started).toBeLessThan(1000);
    expect(samples.length).toBeGreaterThan(drawingPointLimit);
    expect(drawn.length).toBeLessThanOrEqual(drawingPointLimit);
    expect(drawn[0].offset).toBe(0);
    expect(drawn[drawn.length - 1].offset).toBe(synthetic.durationSeconds);
    const source = new Map(samples.map((sample) => [sample.offset, sample.bpm]));
    for (const point of drawn) {
      expect(source.get(point.offset)).toBe(point.bpm);
    }
  });
});
