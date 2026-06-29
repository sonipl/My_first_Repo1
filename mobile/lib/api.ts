import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';

const API_URL =
  (Constants.expoConfig?.extra?.apiUrl as string | undefined) ?? 'http://localhost:8000';

const DEVICE_ID_KEY = 'tesla_tracker_device_id';
const API_TOKEN_KEY = 'tesla_tracker_api_token';

export type DailyUsage = {
  usage_date: string;
  miles_driven: number;
  energy_charged_kwh: number;
  start_odometer_miles: number | null;
  end_odometer_miles: number | null;
  start_battery_percent: number | null;
  end_battery_percent: number | null;
  charging_sessions: number;
  snapshot_count: number;
};

export type Vehicle = {
  id: number;
  vin: string;
  display_name: string;
  model: string | null;
};

export type TodaySummary = {
  vehicle: Vehicle;
  today: DailyUsage | null;
  latest_battery_percent: number | null;
  latest_odometer_miles: number | null;
  connected: boolean;
};

export type StatusResponse = {
  connected: boolean;
  vehicles: Vehicle[];
  next_snapshot: string;
};

async function getCredentials(): Promise<{ deviceId: string; apiToken: string } | null> {
  const deviceId = await AsyncStorage.getItem(DEVICE_ID_KEY);
  const apiToken = await AsyncStorage.getItem(API_TOKEN_KEY);
  if (!deviceId || !apiToken) return null;
  return { deviceId, apiToken };
}

async function ensureRegistered(): Promise<{ deviceId: string; apiToken: string }> {
  const existing = await getCredentials();
  if (existing) return existing;

  const response = await fetch(`${API_URL}/devices/register`, { method: 'POST' });
  if (!response.ok) throw new Error('Failed to register device');
  const data = await response.json();

  await AsyncStorage.setItem(DEVICE_ID_KEY, data.device_id);
  await AsyncStorage.setItem(API_TOKEN_KEY, data.api_token);
  return { deviceId: data.device_id, apiToken: data.api_token };
}

async function apiRequest<T>(path: string, options: RequestInit = {}): Promise<T> {
  const creds = await ensureRegistered();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'X-Device-Id': creds.deviceId,
    Authorization: `Bearer ${creds.apiToken}`,
    ...(options.headers as Record<string, string> | undefined),
  };

  const response = await fetch(`${API_URL}${path}`, { ...options, headers });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(text || `Request failed (${response.status})`);
  }
  return response.json();
}

export const api = {
  getStatus: () => apiRequest<StatusResponse>('/status'),
  getToday: (vehicleId?: number) =>
    apiRequest<TodaySummary>(`/usage/today${vehicleId ? `?vehicle_id=${vehicleId}` : ''}`),
  getHistory: (vehicleId: number, days = 30) =>
    apiRequest<DailyUsage[]>(`/usage/history?vehicle_id=${vehicleId}&days=${days}`),
  connectRefreshToken: (refreshToken: string) =>
    apiRequest<{ status: string; vehicles: Vehicle[] }>('/auth/refresh-token', {
      method: 'POST',
      body: JSON.stringify({ refresh_token: refreshToken }),
    }),
  getAuthUrl: () => apiRequest<{ authorization_url: string }>('/auth/url'),
  syncNow: () =>
    apiRequest<{ synced_at: string; results: unknown[] }>('/agent/sync-now', { method: 'POST' }),
};

export function formatDate(dateStr: string): string {
  const d = new Date(dateStr + 'T12:00:00');
  return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}
