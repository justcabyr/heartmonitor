import 'react-native-gesture-handler';

import { useEffect } from 'react';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { AppState, StyleSheet } from 'react-native';

import { getWatchBridge } from '../src/watch';
import { requestImport, watchForRecordings } from '../src/watch/recordingImport';

const RootLayout = () => {
  useEffect(() => {
    const bridge = getWatchBridge();
    const stop = watchForRecordings(bridge);
    const subscription = AppState.addEventListener('change', (next) => {
      if (next === 'active') {
        void requestImport(bridge);
      }
    });
    return () => {
      stop();
      subscription.remove();
    };
  }, []);

  return (
    <GestureHandlerRootView style={styles.root}>
      <Stack>
        <Stack.Screen name="index" options={{ title: 'History' }} />
        <Stack.Screen name="session/[id]" options={{ title: 'Report' }} />
      </Stack>
    </GestureHandlerRootView>
  );
};

export default RootLayout;

const styles = StyleSheet.create({
  root: {
    flex: 1,
  },
});
