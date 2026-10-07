import { z } from 'zod';

export const heartRateSettingsSchema = z
  .object({
    targetBPM: z.number().min(60).max(230),
    warningFraction: z.number().min(0.5).max(0.99),
    warningCooldown: z.number().min(5).max(600),
    thresholdCooldown: z.number().min(5).max(600),
    hysteresisBPM: z.number().min(1).max(20),
    staleTimeout: z.number().min(1).max(120),
    batteryGuardLevel: z.number().min(0.05).max(0.3),
    saveToHealth: z.boolean(),
  })
  .strict();

export type HeartRateSettings = z.infer<typeof heartRateSettingsSchema>;

export const warningBPM = (settings: HeartRateSettings): number =>
  settings.targetBPM * settings.warningFraction;

export const parseHeartRateSettings = (value: unknown) =>
  heartRateSettingsSchema.safeParse(value);
