import { HeartRateSample, SessionEvent } from '../domain/sessionRecording';

export const gapThresholdSeconds = 60;

export type AggregateBucket = {
  start: number;
  avg?: number;
  min?: number;
  max?: number;
  count?: number;
  gap?: boolean;
  paused?: boolean;
};

type PauseInterval = {
  start: number;
  end: number;
};

const pauseIntervals = (
  events: SessionEvent[],
  endOffset: number,
): PauseInterval[] => {
  const pauses: PauseInterval[] = [];
  let pauseStart: number | null = null;
  const ordered = [...events].sort((left, right) => left.offset - right.offset);
  for (const event of ordered) {
    if (event.kind === 'paused' && pauseStart === null && event.offset < endOffset) {
      pauseStart = event.offset;
    } else if (event.kind === 'resumed' && pauseStart !== null) {
      const end = Math.min(event.offset, endOffset);
      if (end > pauseStart) {
        pauses.push({ start: pauseStart, end });
      }
      pauseStart = null;
    }
  }
  if (pauseStart !== null && endOffset > pauseStart) {
    pauses.push({ start: pauseStart, end: endOffset });
  }
  return pauses;
};

const overlapsPause = (
  start: number,
  end: number,
  pauses: PauseInterval[],
): boolean => pauses.some((pause) => start < pause.end && end > pause.start);

const activeDuration = (
  from: number,
  to: number,
  pauses: PauseInterval[],
): number => {
  let active = Math.max(0, to - from);
  for (const pause of pauses) {
    const overlap = Math.min(to, pause.end) - Math.max(from, pause.start);
    if (overlap > 0) {
      active -= overlap;
    }
  }
  return Math.max(0, active);
};

const isLongGapBucket = (
  start: number,
  end: number,
  samples: HeartRateSample[],
  pauses: PauseInterval[],
  gapThreshold: number,
): boolean => {
  for (let index = 0; index < samples.length - 1; index += 1) {
    const left = samples[index].offset;
    const right = samples[index + 1].offset;
    const overlaps = left < end && right > start;
    if (overlaps && activeDuration(left, right, pauses) > gapThreshold) {
      return true;
    }
  }
  return false;
};

export const spansAreSeparated = (
  from: number,
  to: number,
  events: SessionEvent[],
  endOffset: number,
  gapThreshold: number = gapThresholdSeconds,
): boolean => {
  const start = Math.min(from, to);
  const end = Math.max(from, to);
  const pauses = pauseIntervals(events, endOffset);
  return activeDuration(start, end, pauses) > gapThreshold || overlapsPause(start, end, pauses);
};

export const aggregate = (
  samples: HeartRateSample[],
  events: SessionEvent[],
  intervalSeconds: number,
  endOffset: number,
  gapThreshold: number = gapThresholdSeconds,
): AggregateBucket[] => {
  if (intervalSeconds <= 0) {
    throw new Error('intervalSeconds must be positive');
  }
  const ordered = [...samples].sort((left, right) => left.offset - right.offset);
  const pauses = pauseIntervals(events, endOffset);
  const bucketCount = Math.floor(endOffset / intervalSeconds) + 1;
  const buckets: AggregateBucket[] = [];
  for (let index = 0; index < bucketCount; index += 1) {
    const start = index * intervalSeconds;
    const end = start + intervalSeconds;
    const inBucket = ordered.filter(
      (sample) => sample.offset >= start && sample.offset < end,
    );
    if (inBucket.length > 0) {
      const bpms = inBucket.map((sample) => sample.bpm);
      const sum = bpms.reduce((total, bpm) => total + bpm, 0);
      buckets.push({
        start,
        avg: sum / bpms.length,
        min: Math.min(...bpms),
        max: Math.max(...bpms),
        count: bpms.length,
      });
    } else if (overlapsPause(start, end, pauses)) {
      buckets.push({ start, paused: true });
    } else if (isLongGapBucket(start, end, ordered, pauses, gapThreshold)) {
      buckets.push({ start, gap: true });
    }
  }
  return buckets;
};
