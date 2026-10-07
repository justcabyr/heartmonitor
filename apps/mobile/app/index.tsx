import { useFocusEffect, useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

import { formatAlertCount, formatBPM, formatDuration, formatSessionDate } from '../src/report/format';
import { listSessions, SessionListItem } from '../src/storage/sessionRepository';
import { getWatchBridge } from '../src/watch';
import { requestImport, subscribeImports } from '../src/watch/recordingImport';

const endReasonLabel = {
  user: '',
  batteryGuard: 'Ended to save battery',
  interrupted: 'Interrupted',
  error: 'Ended because of an error',
} as const;

const messageFrom = (error: unknown): string => {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return 'Sessions could not be loaded.';
};

const HistoryScreen = () => {
  const router = useRouter();
  const scheme = useColorScheme();
  const text = scheme === 'dark' ? '#f4f4f5' : '#18181b';
  const muted = scheme === 'dark' ? '#a1a1aa' : '#52525b';
  const card = scheme === 'dark' ? '#27272a' : '#f4f4f5';
  const [sessions, setSessions] = useState<SessionListItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [importError, setImportError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const rows = await listSessions();
      setSessions(rows);
      setLoaded(true);
      setLoadError(null);
    } catch (error) {
      setLoadError(messageFrom(error));
    }
  }, []);

  useFocusEffect(useCallback(() => {
    void requestImport(getWatchBridge());
    void load();
  }, [load]));

  useEffect(() => subscribeImports((error) => {
    setImportError(error);
    void load();
  }), [load]);

  return (
    <FlatList
      data={sessions}
      keyExtractor={(item) => item.id}
      contentContainerStyle={styles.content}
      ListHeaderComponent={importError || loadError ? (
        <View style={styles.headerErrors}>
          {importError ? <Text style={styles.error}>{importError}</Text> : null}
          {loadError ? <Text style={styles.error}>{loadError}</Text> : null}
        </View>
      ) : null}
      ListEmptyComponent={loaded && !loadError ? (
        <View style={styles.empty}>
          <Text style={[styles.title, { color: text }]}>No sessions yet</Text>
          <Text style={[styles.body, { color: text }]}>
            Start a session on your Apple Watch. When you end it, the recording shows up here.
          </Text>
        </View>
      ) : null}
      renderItem={({ item }) => {
        const reason = endReasonLabel[item.endReason];
        const alerts = item.warningEvents + item.thresholdEvents;
        return (
          <Pressable
            style={[styles.row, { backgroundColor: card }]}
            onPress={() => {
              router.push(`/session/${item.id}`);
            }}
          >
            <Text style={[styles.date, { color: text }]}>{formatSessionDate(item.startedAt)}</Text>
            <Text style={[styles.meta, { color: muted }]}>
              {`${formatDuration(item.activeSeconds)} · avg ${formatBPM(item.avgBPM)} · max ${formatBPM(item.maxBPM)} · ${formatAlertCount(alerts)}`}
            </Text>
            {reason ? <Text style={[styles.meta, { color: muted }]}>{reason}</Text> : null}
          </Pressable>
        );
      }}
      ListFooterComponent={(
        <Text style={[styles.disclaimer, { color: muted }]}>
          Personal wellness tool. Not for diagnosis or emergency monitoring.
        </Text>
      )}
    />
  );
};

export default HistoryScreen;

const styles = StyleSheet.create({
  content: {
    flexGrow: 1,
    padding: 16,
    gap: 12,
  },
  empty: {
    flex: 1,
    justifyContent: 'center',
    gap: 12,
    paddingVertical: 24,
  },
  title: {
    fontSize: 28,
    fontWeight: '600',
  },
  body: {
    fontSize: 17,
    lineHeight: 24,
  },
  row: {
    borderRadius: 12,
    padding: 14,
    gap: 4,
  },
  date: {
    fontSize: 17,
    fontWeight: '600',
  },
  meta: {
    fontSize: 15,
    lineHeight: 20,
  },
  headerErrors: {
    gap: 8,
  },
  error: {
    color: '#b42318',
    fontSize: 15,
    lineHeight: 20,
  },
  disclaimer: {
    fontSize: 13,
    lineHeight: 18,
    marginTop: 8,
  },
});
