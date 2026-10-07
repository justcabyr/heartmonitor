import { HeartRateSample } from '../domain/sessionRecording';

export type SyntheticSpec = {
  durationSeconds: number;
  sampleEverySeconds: number;
  baseBPM: number;
  bpmModulus: number;
};

export const syntheticSamples = (spec: SyntheticSpec): HeartRateSample[] => {
  const count = Math.floor(spec.durationSeconds / spec.sampleEverySeconds) + 1;
  return Array.from({ length: count }, (_, index) => ({
    offset: index * spec.sampleEverySeconds,
    bpm: spec.baseBPM + (index % spec.bpmModulus),
  }));
};
