import { HeartRateSample, SessionEvent } from '../domain/sessionRecording';

import { AggregateBucket, spansAreSeparated } from './aggregate';

export const splitSamplesAtBreaks = (
  points: HeartRateSample[],
  source: HeartRateSample[],
  events: SessionEvent[],
  endOffset: number,
): HeartRateSample[][] => {
  const ordered = [...source].sort((left, right) => left.offset - right.offset);
  const breakOffsets: number[] = [];
  for (let index = 1; index < ordered.length; index += 1) {
    const left = ordered[index - 1].offset;
    const right = ordered[index].offset;
    if (spansAreSeparated(left, right, events, endOffset)) {
      breakOffsets.push(left);
    }
  }

  const drawn = [...points].sort((left, right) => left.offset - right.offset);
  if (drawn.length === 0) {
    return [];
  }
  const segments: HeartRateSample[][] = [[drawn[0]]];
  for (let index = 1; index < drawn.length; index += 1) {
    const previous = drawn[index - 1].offset;
    const current = drawn[index].offset;
    const broken = breakOffsets.some((offset) => offset >= previous && offset < current);
    if (broken) {
      segments.push([drawn[index]]);
    } else {
      segments[segments.length - 1].push(drawn[index]);
    }
  }
  return segments;
};

export const dataBucketSegments = (buckets: AggregateBucket[]): AggregateBucket[][] => {
  const segments: AggregateBucket[][] = [];
  let current: AggregateBucket[] = [];
  for (const bucket of buckets) {
    const hasAverage = bucket.avg !== undefined && !bucket.gap && !bucket.paused;
    if (!hasAverage) {
      if (current.length > 0) {
        segments.push(current);
        current = [];
      }
      continue;
    }
    current.push(bucket);
  }
  if (current.length > 0) {
    segments.push(current);
  }
  return segments;
};
