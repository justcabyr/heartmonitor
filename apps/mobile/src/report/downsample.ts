import { HeartRateSample } from '../domain/sessionRecording';

export const drawingPointLimit = 1500;

export const downsample = (
  samples: HeartRateSample[],
  maxPoints: number = drawingPointLimit,
): HeartRateSample[] => {
  if (maxPoints < 2) {
    throw new Error('maxPoints must be at least 2');
  }
  const ordered = [...samples].sort((left, right) => left.offset - right.offset);
  if (ordered.length <= maxPoints) {
    return ordered.map((sample) => ({ ...sample }));
  }

  const first = ordered[0];
  const last = ordered[ordered.length - 1];
  const interior = ordered.slice(1, -1);
  const picks = new Map<number, HeartRateSample>();
  picks.set(first.offset, first);
  picks.set(last.offset, last);

  const windowCount = Math.max(1, Math.floor((maxPoints - 2) / 2));
  const windowSize = Math.ceil(interior.length / windowCount);
  for (let window = 0; window < windowCount; window += 1) {
    const slice = interior.slice(window * windowSize, (window + 1) * windowSize);
    if (slice.length === 0) {
      continue;
    }
    let lowest = slice[0];
    let highest = slice[0];
    for (const sample of slice) {
      if (
        sample.bpm < lowest.bpm
        || (sample.bpm === lowest.bpm && sample.offset < lowest.offset)
      ) {
        lowest = sample;
      }
      if (
        sample.bpm > highest.bpm
        || (sample.bpm === highest.bpm && sample.offset > highest.offset)
      ) {
        highest = sample;
      }
    }
    picks.set(lowest.offset, lowest);
    picks.set(highest.offset, highest);
  }

  return [...picks.values()].sort((left, right) => left.offset - right.offset);
};
