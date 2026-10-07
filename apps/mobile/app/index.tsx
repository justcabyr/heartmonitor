import { StyleSheet, Text, View } from 'react-native';

const HistoryScreen = () => (
  <View style={styles.screen}>
    <Text style={styles.title}>No sessions yet</Text>
    <Text style={styles.body}>
      Start a session on your Apple Watch. When you end it, the recording shows up here.
    </Text>
    <Text style={styles.disclaimer}>
      Personal wellness tool. Not for diagnosis or emergency monitoring.
    </Text>
  </View>
);

export default HistoryScreen;

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    justifyContent: 'center',
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
  disclaimer: {
    fontSize: 13,
    lineHeight: 18,
  },
});
