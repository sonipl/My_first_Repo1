import * as Linking from 'expo-linking';
import { Link } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';

import { StatusResponse, api } from '@/lib/api';

export default function SettingsScreen() {
  const [loading, setLoading] = useState(true);
  const [connecting, setConnecting] = useState(false);
  const [status, setStatus] = useState<StatusResponse | null>(null);
  const [refreshToken, setRefreshToken] = useState('');
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const data = await api.getStatus();
      setStatus(data);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load status');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const connectWithOAuth = async () => {
    setConnecting(true);
    setError(null);
    try {
      const { authorization_url } = await api.getAuthUrl();
      await Linking.openURL(authorization_url);
      Alert.alert(
        'Complete sign-in in browser',
        'After authorizing Tesla, return here and pull to refresh on the Today screen.',
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : 'OAuth failed');
    } finally {
      setConnecting(false);
    }
  };

  const connectWithToken = async () => {
    if (!refreshToken.trim()) {
      Alert.alert('Missing token', 'Paste your Tesla refresh token first.');
      return;
    }
    setConnecting(true);
    setError(null);
    try {
      await api.connectRefreshToken(refreshToken.trim());
      setRefreshToken('');
      await load();
      Alert.alert('Connected', 'Your Tesla account is linked.');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Connection failed');
    } finally {
      setConnecting(false);
    }
  };

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#e82127" />
      </View>
    );
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.card}>
        <Text style={styles.cardTitle}>Connection status</Text>
        <View style={styles.statusRow}>
          <View style={[styles.dot, status?.connected ? styles.dotOn : styles.dotOff]} />
          <Text style={styles.statusText}>
            {status?.connected ? 'Tesla account connected' : 'Not connected'}
          </Text>
        </View>
        {status?.connected ? (
          <Text style={styles.hint}>Daily agent runs at {status.next_snapshot}</Text>
        ) : null}
      </View>

      {status?.vehicles.length ? (
        <View style={styles.card}>
          <Text style={styles.cardTitle}>Your vehicles</Text>
          {status.vehicles.map((v) => (
            <View key={v.id} style={styles.vehicleRow}>
              <Text style={styles.vehicleName}>{v.display_name}</Text>
              <Text style={styles.vehicleVin}>{v.vin}</Text>
            </View>
          ))}
        </View>
      ) : null}

      {error ? (
        <View style={styles.errorBox}>
          <Text style={styles.errorText}>{error}</Text>
        </View>
      ) : null}

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Connect with refresh token</Text>
        <Text style={styles.helpText}>
          Register at developer.tesla.com, create a Fleet API app, then generate a refresh token for your account.
        </Text>
        <TextInput
          style={styles.input}
          placeholder="Paste Tesla refresh token"
          placeholderTextColor="#555"
          value={refreshToken}
          onChangeText={setRefreshToken}
          autoCapitalize="none"
          autoCorrect={false}
          secureTextEntry
        />
        <Pressable style={styles.primaryButton} onPress={connectWithToken} disabled={connecting}>
          <Text style={styles.primaryButtonText}>{connecting ? 'Connecting…' : 'Connect'}</Text>
        </Pressable>
      </View>

      <View style={styles.card}>
        <Text style={styles.cardTitle}>Connect with Tesla OAuth</Text>
        <Text style={styles.helpText}>
          Opens Tesla sign-in in your browser. Requires backend OAuth redirect configured.
        </Text>
        <Pressable style={styles.secondaryButton} onPress={connectWithOAuth} disabled={connecting}>
          <Text style={styles.secondaryButtonText}>Sign in with Tesla</Text>
        </Pressable>
      </View>

      <Link href="/" asChild>
        <Pressable style={styles.linkButton}>
          <Text style={styles.linkText}>← Back to Today</Text>
        </Pressable>
      </Link>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#0a0a0a' },
  container: { padding: 20, paddingBottom: 40, gap: 16 },
  card: {
    backgroundColor: '#141414',
    borderRadius: 14,
    padding: 16,
    borderWidth: 1,
    borderColor: '#222',
    gap: 10,
  },
  cardTitle: { color: '#fff', fontSize: 16, fontWeight: '600' },
  statusRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  dot: { width: 10, height: 10, borderRadius: 5 },
  dotOn: { backgroundColor: '#4ade80' },
  dotOff: { backgroundColor: '#666' },
  statusText: { color: '#ddd', fontSize: 15 },
  hint: { color: '#888', fontSize: 13 },
  vehicleRow: { paddingVertical: 8, borderTopWidth: 1, borderTopColor: '#222' },
  vehicleName: { color: '#fff', fontSize: 15, fontWeight: '500' },
  vehicleVin: { color: '#666', fontSize: 12, marginTop: 2 },
  errorBox: { backgroundColor: '#3a1515', padding: 12, borderRadius: 10 },
  errorText: { color: '#ff8a8a', fontSize: 13 },
  helpText: { color: '#888', fontSize: 13, lineHeight: 18 },
  input: {
    backgroundColor: '#0a0a0a',
    borderWidth: 1,
    borderColor: '#333',
    borderRadius: 10,
    padding: 14,
    color: '#fff',
    fontSize: 14,
    marginTop: 4,
  },
  primaryButton: {
    backgroundColor: '#e82127',
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 8,
  },
  primaryButtonText: { color: '#fff', fontWeight: '700', fontSize: 15 },
  secondaryButton: {
    borderWidth: 1,
    borderColor: '#e82127',
    paddingVertical: 14,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 4,
  },
  secondaryButtonText: { color: '#e82127', fontWeight: '600', fontSize: 15 },
  linkButton: { alignItems: 'center', paddingVertical: 16 },
  linkText: { color: '#888', fontSize: 15 },
});
