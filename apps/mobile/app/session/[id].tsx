import { useLocalSearchParams } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

const ReportScreen = () => {
  const { id } = useLocalSearchParams<{ id: string }>();

  return (
    <View style={styles.screen}>
      <Text style={styles.title}>Report</Text>
      <Text style={styles.body}>
        The chart for this session will appear here once the recording is on this iPhone.
      </Text>
      <Text style={styles.id}>{id}</Text>
      <Text style={styles.disclaimer}>
        Personal wellness tool. Not for diagnosis or emergency monitoring.
      </Text>
    </View>
  );
};

export default ReportScreen;

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    padding: 24,
    gap: 12,
  },
  title: {
    fontSize: 28,
    fontWeight: '600',
  },
  body: {
    fontSize: 17,
    lineHeight: 24,
  },
  id: {
    fontSize: 13,
  },
  disclaimer: {
    fontSize: 13,
    lineHeight: 18,
  },
});
