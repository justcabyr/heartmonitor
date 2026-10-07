import { z } from 'zod';

import { heartRateSettingsSchema } from './heartRateSettings';

export const sessionEventKindSchema = z.enum([
  'warning',
  'threshold',
  'staleStart',
  'staleEnd',
  'paused',
  'resumed',
  'recovered',
  'batteryGuard',
  'settingsChanged',
]);

export const endReasonSchema = z.enum([
  'user',
  'batteryGuard',
  'interrupted',
  'error',
]);

export const sourcePlatformSchema = z.enum(['watchos', 'wearos', 'garmin']);

export const heartRateSampleSchema = z
  .object({
    offset: z.number().finite().nonnegative(),
    bpm: z.number().finite(),
  })
  .strict();

export const sessionEventSchema = z
  .object({
    offset: z.number().finite().nonnegative(),
    kind: sessionEventKindSchema,
  })
  .strict();

export const monitoringSummarySchema = z
  .object({
    id: z.string().uuid(),
    startedAt: z.string().datetime({ offset: true }),
    endedAt: z.string().datetime({ offset: true }),
    activeSeconds: z.number().finite().nonnegative(),
    sampleCount: z.number().int().nonnegative(),
    avgBPM: z.number().finite(),
    minBPM: z.number().finite(),
    maxBPM: z.number().finite(),
    warningEvents: z.number().int().nonnegative(),
    thresholdEvents: z.number().int().nonnegative(),
    secondsAboveWarning: z.number().finite().nonnegative(),
    secondsAboveTarget: z.number().finite().nonnegative(),
    gapSeconds: z.number().finite().nonnegative(),
    endReason: endReasonSchema,
  })
  .strict();

export const sessionRecordingSchema = z
  .object({
    schemaVersion: z.literal(1),
    id: z.string().uuid(),
    sourcePlatform: sourcePlatformSchema,
    deviceModel: z.string().min(1),
    watchAppVersion: z.string().min(1),
    startedAt: z.string().datetime({ offset: true }),
    settings: heartRateSettingsSchema,
    samples: z.array(heartRateSampleSchema),
    events: z.array(sessionEventSchema),
    summary: monitoringSummarySchema,
  })
  .strict();

export type SessionEventKind = z.infer<typeof sessionEventKindSchema>;
export type EndReason = z.infer<typeof endReasonSchema>;
export type SourcePlatform = z.infer<typeof sourcePlatformSchema>;
export type HeartRateSample = z.infer<typeof heartRateSampleSchema>;
export type SessionEvent = z.infer<typeof sessionEventSchema>;
export type MonitoringSummary = z.infer<typeof monitoringSummarySchema>;
export type SessionRecording = z.infer<typeof sessionRecordingSchema>;

export const parseSessionRecording = (value: unknown) =>
  sessionRecordingSchema.safeParse(value);
