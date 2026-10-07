import { HeartRateSample } from '../domain/sessionRecording';

import { AggregateBucket } from './aggregate';

const formatNumber = (value: number): string => {
  if (!Number.isFinite(value)) {
    throw new Error('CSV values must be finite');
  }
  return String(value);
};

export const samplesToCsv = (samples: HeartRateSample[]): string => {
  const lines = ['offset_s,bpm'];
  for (const sample of samples) {
    lines.push(`${formatNumber(sample.offset)},${formatNumber(sample.bpm)}`);
  }
  return `${lines.join('\n')}\n`;
};

export const bucketsToCsv = (buckets: AggregateBucket[]): string => {
  const lines = ['start_s,avg_bpm,min_bpm,max_bpm,count,gap,paused'];
  for (const bucket of buckets) {
    if (bucket.gap || bucket.paused) {
      lines.push(
        [
          formatNumber(bucket.start),
          '',
          '',
          '',
          '',
          bucket.gap ? 'true' : 'false',
          bucket.paused ? 'true' : 'false',
        ].join(','),
      );
    } else {
      lines.push(
        [
          formatNumber(bucket.start),
          formatNumber(bucket.avg ?? 0),
          formatNumber(bucket.min ?? 0),
          formatNumber(bucket.max ?? 0),
          formatNumber(bucket.count ?? 0),
          'false',
          'false',
        ].join(','),
      );
    }
  }
  return `${lines.join('\n')}\n`;
};
