export const formatDuration = (seconds: number): string => {
  if (!Number.isFinite(seconds) || seconds < 0) {
    throw new Error('Duration must be a finite number of seconds.');
  }
  const total = Math.round(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const remainder = total % 60;
  const pad = (value: number) => String(value).padStart(2, '0');
  if (hours > 0) {
    return `${hours}:${pad(minutes)}:${pad(remainder)}`;
  }
  return `${minutes}:${pad(remainder)}`;
};

export const formatBPM = (bpm: number): string => {
  if (!Number.isFinite(bpm)) {
    throw new Error('BPM must be a finite number.');
  }
  return String(Math.round(bpm));
};

export const formatSessionDate = (iso: string): string => {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    throw new Error('The session date could not be read.');
  }
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
};

export const formatAlertCount = (count: number): string => {
  if (!Number.isInteger(count) || count < 0) {
    throw new Error('Alert count must be a whole number.');
  }
  return count === 1 ? '1 alert' : `${count} alerts`;
};
