import { File, Paths } from 'expo-file-system';
import { useLocalSearchParams } from 'expo-router';
import * as Sharing from 'expo-sharing';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

import { warningBPM } from '../../src/domain/heartRateSettings';
import { SessionRecording } from '../../src/domain/sessionRecording';
import { aggregate } from '../../src/report/aggregate';
import { bucketsToCsv, samplesToCsv } from '../../src/report/csv';
import { formatAlertCount, formatBPM, formatDuration, formatSessionDate } from '../../src/report/format';
import { intervalChoices, ReportInterval } from '../../src/report/intervals';
import { SessionChart } from '../../src/report/SessionChart';
import { sessionEndOffset } from '../../src/report/sessionWindow';
import { loadRecording } from '../../src/storage/sessionRepository';

const messageFrom = (error: unknown): string => {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return 'This report could not be opened.';
};

const ReportScreen = () => {
  const params = useLocalSearchParams<{ id: string }>();
  const id = Array.isArray(params.id) ? params.id[0] : params.id;
  const scheme = useColorScheme();
  const text = scheme === 'dark' ? '#f4f4f5' : '#18181b';
  const muted = scheme === 'dark' ? '#a1a1aa' : '#52525b';
  const card = scheme === 'dark' ? '#27272a' : '#f4f4f5';
  const selected = scheme === 'dark' ? '#3f3f46' : '#e4e4e7';
  const [recording, setRecording] = useState<SessionRecording | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [interval, setInterval] = useState<ReportInterval>(60);
  const [exporting, setExporting] = useState(false);

  useEffect(() => {
    let active = true;
    if (!id) {
      setError('This session id is not valid.');
      return undefined;
    }
    setRecording(null);
    loadRecording(id)
      .then((value) => {
        if (active) {
          setRecording(value);
          setError(null);
        }
      })
      .catch((loadError: unknown) => {
        if (active) {
          setError(messageFrom(loadError));
        }
      });
    return () => {
      active = false;
    };
  }, [id]);

  const exportCsv = async () => {
    if (!recording || exporting) {
      return;
    }
    setExporting(true);
    try {
      const available = await Sharing.isAvailableAsync();
      if (!available) {
        throw new Error('Sharing is not available on this iPhone.');
      }
      const csv = interval === 'raw'
        ? samplesToCsv(recording.samples)
        : bucketsToCsv(aggregate(
          recording.samples,
          recording.events,
          interval,
          sessionEndOffset(recording),
        ));
      const file = new File(Paths.cache, `heartthreshold-${recording.id}.csv`);
      file.write(csv);
      await Sharing.shareAsync(file.uri, {
        UTI: 'public.comma-separated-values-text',
        mimeType: 'text/csv',
      });
      setError(null);
    } catch (exportError) {
      setError(messageFrom(exportError));
    } finally {
      setExporting(false);
    }
  };

  if (!recording) {
    return (
      <View style={styles.centered}>
        {error ? (
          <Text style={styles.error}>{error}</Text>
        ) : (
          <ActivityIndicator />
        )}
      </View>
    );
  }

  const summary = recording.summary;
  const alerts = summary.warningEvents + summary.thresholdEvents;
  const stats = [
    ['Duration', formatDuration(summary.activeSeconds)],
    ['Average', `${formatBPM(summary.avgBPM)} BPM`],
    ['Min', `${formatBPM(summary.minBPM)} BPM`],
    ['Max', `${formatBPM(summary.maxBPM)} BPM`],
    ['Above warning', formatDuration(summary.secondsAboveWarning)],
    ['Above target', formatDuration(summary.secondsAboveTarget)],
    ['Alerts', formatAlertCount(alerts)],
    ['Gaps', formatDuration(summary.gapSeconds)],
  ];
  const chartCaption = interval === 'raw'
    ? 'Line is heart rate. Gold is the warning. Red is the alert target. Breaks are gaps or pauses.'
    : 'Line is the average. The band is min–max. Gold is the warning. Red is the alert target. Breaks are gaps or pauses.';

  return (
    <ScrollView contentContainerStyle={styles.content}>
      <Text style={[styles.date, { color: text }]}>{formatSessionDate(recording.startedAt)}</Text>
      <Text style={[styles.meta, { color: muted }]}>
        {`Alert at ${formatBPM(recording.settings.targetBPM)} · warn at ${formatBPM(warningBPM(recording.settings))}`}
      </Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <View style={styles.chips}>
        {intervalChoices.map((choice) => {
          const isSelected = choice.id === interval;
          return (
            <Pressable
              key={choice.label}
              style={[styles.chip, { backgroundColor: isSelected ? selected : card }]}
              onPress={() => {
                setInterval(choice.id);
              }}
            >
              <Text style={[styles.chipLabel, { color: text }]}>{choice.label}</Text>
            </Pressable>
          );
        })}
      </View>
      <View style={styles.chart}>
        <SessionChart recording={recording} interval={interval} />
      </View>
      <Text style={[styles.caption, { color: muted }]}>{chartCaption}</Text>
      <View style={styles.stats}>
        {stats.map(([label, value]) => (
          <View key={label} style={[styles.stat, { backgroundColor: card }]}>
            <Text style={[styles.statLabel, { color: muted }]}>{label}</Text>
            <Text style={[styles.statValue, { color: text }]}>{value}</Text>
          </View>
        ))}
      </View>
      <Pressable
        style={[styles.export, { backgroundColor: card }]}
        onPress={() => {
          void exportCsv();
        }}
        disabled={exporting}
      >
        <Text style={[styles.exportLabel, { color: text }]}>
          {exporting ? 'Exporting…' : 'Export CSV'}
        </Text>
      </Pressable>
      <Text style={[styles.disclaimer, { color: muted }]}>
        Personal wellness tool. Not for diagnosis or emergency monitoring.
      </Text>
    </ScrollView>
  );
};

export default ReportScreen;

const styles = StyleSheet.create({
  centered: {
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  content: {
    padding: 16,
    gap: 12,
  },
  date: {
    fontSize: 22,
    fontWeight: '600',
  },
  meta: {
    fontSize: 15,
  },
  chips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  chip: {
    borderRadius: 999,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  chipLabel: {
    fontSize: 15,
    fontWeight: '600',
  },
  chart: {
    height: 240,
  },
  caption: {
    fontSize: 13,
    lineHeight: 18,
  },
  stats: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  stat: {
    width: '48%',
    flexGrow: 1,
    borderRadius: 12,
    padding: 12,
    gap: 4,
  },
  statLabel: {
    fontSize: 13,
  },
  statValue: {
    fontSize: 18,
    fontWeight: '600',
  },
  export: {
    borderRadius: 12,
    padding: 14,
    alignItems: 'center',
  },
  exportLabel: {
    fontSize: 17,
    fontWeight: '600',
  },
  error: {
    color: '#b42318',
    fontSize: 15,
    lineHeight: 20,
  },
  disclaimer: {
    fontSize: 13,
    lineHeight: 18,
  },
});
