import { Stack } from 'expo-router';

const RootLayout = () => (
  <Stack>
    <Stack.Screen name="index" options={{ title: 'History' }} />
    <Stack.Screen name="session/[id]" options={{ title: 'Report' }} />
  </Stack>
);

export default RootLayout;
