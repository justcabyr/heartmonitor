import fs from 'fs';

import { SessionEvent } from '../domain/sessionRecording';
import { contractsPath } from '../test/contractsPath';

import { aggregate } from './aggregate';
import { bucketsToCsv, samplesToCsv } from './csv';

describe('csv', () => {
  test('writes every raw sample and does not invent rows', () => {
    const csv = samplesToCsv([
      { offset: 0, bpm: 70 },
      { offset: 30, bpm: 80 },
      { offset: 200, bpm: 90 },
    ]);
    expect(csv).toBe('offset_s,bpm\n0,70\n30,80\n200,90\n');
  });

  test('writes the selected interval, including gap and pause breaks', () => {
    const file = JSON.parse(
      fs.readFileSync(contractsPath('aggregation-test-vectors.json'), 'utf8'),
    ) as Array<{
      name: string;
      intervalSeconds: number;
      samples: Array<{ t: number; bpm: number }>;
      events: Array<{ t: number; kind: SessionEvent['kind'] }>;
      summary: { endOffset: number };
    }>;
    const vector = file.find((item) => item.name === '1-minute buckets with a gap and a pause');
    expect(vector).toBeDefined();
    if (!vector) return;
    const buckets = aggregate(
      vector.samples.map((sample) => ({ offset: sample.t, bpm: sample.bpm })),
      vector.events.map((event) => ({ offset: event.t, kind: event.kind })),
      vector.intervalSeconds,
      vector.summary.endOffset,
    );
    const csv = bucketsToCsv(buckets);
    expect(csv.split('\n')[0]).toBe('start_s,avg_bpm,min_bpm,max_bpm,count,gap,paused');
    expect(csv).toContain('0,75,70,80,2,false,false');
    expect(csv).toContain('60,,,,,true,false');
    expect(csv).toContain('240,,,,,false,true');
    expect(csv.trim().split('\n')).toHaveLength(buckets.length + 1);
  });
});
