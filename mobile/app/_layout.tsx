import { Stack, Link } from 'expo-router';
import { Pressable, Text } from 'react-native';
import { StatusBar } from 'expo-status-bar';

function HeaderLink({ href, label }: { href: '/history' | '/settings'; label: string }) {
  return (
    <Link href={href} asChild>
      <Pressable style={{ paddingHorizontal: 8 }}>
        <Text style={{ color: '#e82127', fontSize: 15, fontWeight: '600' }}>{label}</Text>
      </Pressable>
    </Link>
  );
}

export default function RootLayout() {
  return (
    <>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: '#0a0a0a' },
          headerTintColor: '#fff',
          headerTitleStyle: { fontWeight: '600' },
          contentStyle: { backgroundColor: '#0a0a0a' },
        }}
      >
        <Stack.Screen
          name="index"
          options={{
            title: 'Today',
            headerRight: () => (
              <>
                <HeaderLink href="/history" label="History" />
                <HeaderLink href="/settings" label="Settings" />
              </>
            ),
          }}
        />
        <Stack.Screen name="history" options={{ title: 'History' }} />
        <Stack.Screen name="settings" options={{ title: 'Settings' }} />
      </Stack>
    </>
  );
}
