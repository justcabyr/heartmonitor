export const intervalChoices = [
  { id: 'raw', label: 'Raw' },
  { id: 60, label: '1 min' },
  { id: 300, label: '5 min' },
  { id: 900, label: '15 min' },
] as const;

export type ReportInterval = (typeof intervalChoices)[number]['id'];
