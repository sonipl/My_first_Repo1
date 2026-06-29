import { Link } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { TodaySummary, api } from '@/lib/api';

function StatCard({
  label,
  value,
  unit,
  accent,
}: {
  label: string;
  value: string;
  unit?: string;
  accent?: string;
}) {
  return (
    <View style={styles.statCard}>
      <Text style={styles.statLabel}>{label}</Text>
      <View style={styles.statValueRow}>
        <Text style={[styles.statValue, accent ? { color: accent } : null]}>{value}</Text>
        {unit ? <Text style={styles.statUnit}>{unit}</Text> : null}
      </View>
    </View>
  );
}

export default function HomeScreen() {
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<TodaySummary | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const data = await api.getToday();
      setSummary(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load data');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const onRefresh = async () => {
    setRefreshing(true);
    await load();
  };

  const onSync = async () => {
    setRefreshing(true);
    try {
      await api.syncNow();
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sync failed');
      setRefreshing(false);
    }
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#e82127" />
      </View>
    );
  }

  const today = summary?.today;
  const vehicle = summary?.vehicle;

  return (
    <ScrollView
      contentContainerStyle={styles.container}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#e82127" />}
    >
      {!summary?.connected ? (
        <View style={styles.banner}>
          <Text style={styles.bannerTitle}>Connect your Tesla</Text>
          <Text style={styles.bannerText}>
            Link your account in Settings to start tracking daily miles, charging, and battery usage.
          </Text>
          <Link href="/settings" asChild>
            <Pressable style={styles.bannerButton}>
              <Text style={styles.bannerButtonText}>Go to Settings</Text>
            </Pressable>
          </Link>
        </View>
      ) : null}

      {error ? (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      ) : null}

      {vehicle ? (
        <View style={styles.vehicleHeader}>
          <Text style={styles.vehicleName}>{vehicle.display_name}</Text>
          <Text style={styles.vehicleMeta}>{vehicle.model ?? 'Tesla'} · {vehicle.vin.slice(-6)}</Text>
        </View>
      ) : null}

      <View style={styles.grid}>
        <StatCard
          label="Miles today"
          value={today ? today.miles_driven.toFixed(1) : '—'}
          unit="mi"
          accent="#e82127"
        />
        <StatCard
          label="Energy charged"
          value={today ? today.energy_charged_kwh.toFixed(1) : '—'}
          unit="kWh"
        />
        <StatCard
          label="Battery"
          value={summary?.latest_battery_percent != null ? `${Math.round(summary.latest_battery_percent)}` : '—'}
          unit="%"
        />
        <StatCard
          label="Odometer"
          value={
            summary?.latest_odometer_miles != null
              ? summary.latest_odometer_miles.toLocaleString(undefined, { maximumFractionDigits: 0 })
              : '—'
          }
          unit="mi"
        />
      </View>

      {today ? (
        <View style={styles.detailCard}>
          <Text style={styles.detailTitle}>Today&apos;s breakdown</Text>
          <DetailRow label="Start odometer" value={`${today.start_odometer_miles?.toFixed(1) ?? '—'} mi`} />
          <DetailRow label="End odometer" value={`${today.end_odometer_miles?.toFixed(1) ?? '—'} mi`} />
          <DetailRow
            label="Battery"
            value={`${today.start_battery_percent ?? '—'}% → ${today.end_battery_percent ?? '—'}%`}
          />
          <DetailRow label="Charging sessions" value={String(today.charging_sessions)} />
          <DetailRow label="Snapshots" value={String(today.snapshot_count)} />
        </View>
      ) : (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyTitle}>No data for today yet</Text>
          <Text style={styles.emptyText}>
            The daily agent captures usage automatically. Tap Sync Now to fetch the latest reading from your car.
          </Text>
        </View>
      )}

      <Pressable style={styles.syncButton} onPress={onSync} disabled={refreshing || !summary?.connected}>
        <Text style={styles.syncButtonText}>{refreshing ? 'Syncing…' : 'Sync Now'}</Text>
      </Pressable>

      <Link href="/history" asChild>
        <Pressable style={styles.linkButton}>
          <Text style={styles.linkButtonText}>View 30-day history →</Text>
        </Pressable>
      </Link>
    </ScrollView>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.detailRow}>
      <Text style={styles.detailLabel}>{label}</Text>
      <Text style={styles.detailValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0a0a0a' },
  container: { padding: 20, paddingBottom: 40, gap: 16 },
  banner: {
    backgroundColor: '#1a1a1a',
    borderRadius: 16,
    padding: 20,
    borderWidth: 1,
    borderColor: '#e8212733',
  },
  bannerTitle: { color: '#fff', fontSize: 18, fontWeight: '700', marginBottom: 8 },
  bannerText: { color: '#aaa', fontSize: 14, lineHeight: 20, marginBottom: 16 },
  bannerButton: {
    backgroundColor: '#e82127',
    paddingVertical: 12,
    borderRadius: 10,
    alignItems: 'center',
  },
  bannerButtonText: { color: '#fff', fontWeight: '600' },
  errorBox: { backgroundColor: '#3a1515', padding: 12, borderRadius: 10 },
  errorText: { color: '#ff8a8a', fontSize: 13 },
  vehicleHeader: { marginBottom: 4 },
  vehicleName: { color: '#fff', fontSize: 24, fontWeight: '700' },
  vehicleMeta: { color: '#888', fontSize: 13, marginTop: 4 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12 },
  statCard: {
    backgroundColor: '#141414',
    borderRadius: 14,
    padding: 16,
    width: '47%',
    flexGrow: 1,
    borderWidth: 1,
    borderColor: '#222',
  },
  statLabel: { color: '#888', fontSize: 12, marginBottom: 8, textTransform: 'uppercase', letterSpacing: 0.5 },
  statValueRow: { flexDirection: 'row', alignItems: 'baseline', gap: 4 },
  statValue: { color: '#fff', fontSize: 28, fontWeight: '700' },
  statUnit: { color: '#666', fontSize: 14 },
  detailCard: {
    backgroundColor: '#141414',
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: '#222',
    gap: 10,
  },
  detailTitle: { color: '#fff', fontSize: 16, fontWeight: '600', marginBottom: 4 },
  detailRow: { flexDirection: 'row', justifyContent: 'space-between' },
  detailLabel: { color: '#888', fontSize: 14 },
  detailValue: { color: '#ddd', fontSize: 14, fontWeight: '500' },
  emptyCard: {
    backgroundColor: '#141414',
    borderRadius: 14,
    padding: 20,
    borderWidth: 1,
    borderColor: '#222',
  },
  emptyTitle: { color: '#fff', fontSize: 16, fontWeight: '600', marginBottom: 8 },
  emptyText: { color: '#888', fontSize: 14, lineHeight: 20 },
  syncButton: {
    backgroundColor: '#e82127',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 8,
  },
  syncButtonText: { color: '#fff', fontSize: 16, fontWeight: '700' },
  linkButton: { alignItems: 'center', paddingVertical: 12 },
  linkButtonText: { color: '#e82127', fontSize: 15, fontWeight: '600' },
});
