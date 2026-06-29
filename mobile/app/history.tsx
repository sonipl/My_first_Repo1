import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { DailyUsage, Vehicle, api, formatDate } from '@/lib/api';

export default function HistoryScreen() {
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [history, setHistory] = useState<DailyUsage[]>([]);
  const [vehicle, setVehicle] = useState<Vehicle | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const status = await api.getStatus();
      const primary = status.vehicles[0];
      if (!primary) {
        setHistory([]);
        return;
      }
      setVehicle(primary);
      const data = await api.getHistory(primary.id, 30);
      setHistory(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load history');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#e82127" />
      </View>
    );
  }

  const totalMiles = history.reduce((sum, d) => sum + d.miles_driven, 0);
  const totalEnergy = history.reduce((sum, d) => sum + d.energy_charged_kwh, 0);

  return (
    <ScrollView
      contentContainerStyle={styles.container}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={() => { setRefreshing(true); load(); }} tintColor="#e82127" />
      }
    >
      {vehicle ? (
        <Text style={styles.subtitle}>{vehicle.display_name} — last 30 days</Text>
      ) : null}

      {error ? (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      ) : null}

      <View style={styles.summaryRow}>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryValue}>{totalMiles.toFixed(0)}</Text>
          <Text style={styles.summaryLabel}>Total miles</Text>
        </View>
        <View style={styles.summaryCard}>
          <Text style={styles.summaryValue}>{totalEnergy.toFixed(0)}</Text>
          <Text style={styles.summaryLabel}>kWh charged</Text>
        </View>
      </View>

      {history.length === 0 ? (
        <Text style={styles.empty}>No history yet. Connect Tesla and sync to start tracking.</Text>
      ) : (
        history.map((day) => (
          <View key={day.usage_date} style={styles.row}>
            <View>
              <Text style={styles.date}>{formatDate(day.usage_date)}</Text>
              <Text style={styles.meta}>
                {day.charging_sessions} charge{day.charging_sessions === 1 ? '' : 's'}
              </Text>
            </View>
            <View style={styles.rowStats}>
              <Text style={styles.miles}>{day.miles_driven.toFixed(1)} mi</Text>
              <Text style={styles.energy}>{day.energy_charged_kwh.toFixed(1)} kWh</Text>
            </View>
          </View>
        ))
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0a0a0a' },
  container: { padding: 20, paddingBottom: 40 },
  subtitle: { color: '#888', fontSize: 14, marginBottom: 16 },
  errorBox: { backgroundColor: '#3a1515', padding: 12, borderRadius: 10, marginBottom: 16 },
  errorText: { color: '#ff8a8a', fontSize: 13 },
  summaryRow: { flexDirection: 'row', gap: 12, marginBottom: 20 },
  summaryCard: {
    flex: 1,
    backgroundColor: '#141414',
    borderRadius: 14,
    padding: 16,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#222',
  },
  summaryValue: { color: '#e82127', fontSize: 28, fontWeight: '700' },
  summaryLabel: { color: '#888', fontSize: 12, marginTop: 4 },
  empty: { color: '#888', textAlign: 'center', marginTop: 40, fontSize: 15 },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 14,
    borderBottomWidth: 1,
    borderBottomColor: '#1e1e1e',
  },
  date: { color: '#fff', fontSize: 15, fontWeight: '600' },
  meta: { color: '#666', fontSize: 12, marginTop: 2 },
  rowStats: { alignItems: 'flex-end' },
  miles: { color: '#fff', fontSize: 16, fontWeight: '600' },
  energy: { color: '#888', fontSize: 13, marginTop: 2 },
});
