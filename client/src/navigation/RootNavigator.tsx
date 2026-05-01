import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {Library, Settings} from 'lucide-react-native';

import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {AddServerScreen} from '../screens/AddServerScreen';
import {ArchiveDetailScreen} from '../screens/ArchiveDetailScreen';
import {HomeScreen} from '../screens/HomeScreen';
import {LoginScreen} from '../screens/LoginScreen';
import {ReaderScreen} from '../screens/ReaderScreen';
import {ServerListScreen} from '../screens/ServerListScreen';
import {SettingsScreen} from '../screens/SettingsScreen';
import {colors} from '../theme/colors';
import type {MainTabParamList, RootStackParamList} from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<MainTabParamList>();

function LibraryTabIcon({color, size}: {color: string; size: number}) {
  return <Library color={color} size={size} />;
}

function SettingsTabIcon({color, size}: {color: string; size: number}) {
  return <Settings color={color} size={size} />;
}

function MainTabs() {
  return (
    <Tabs.Navigator
      screenOptions={{
        headerStyle: {backgroundColor: colors.surface},
        headerTitleStyle: {color: colors.text, fontWeight: '700'},
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textMuted,
      }}>
      <Tabs.Screen
        name="Home"
        component={HomeScreen}
        options={{
          title: 'Library',
          tabBarLabel: 'Library',
          tabBarIcon: LibraryTabIcon,
        }}
      />
      <Tabs.Screen
        name="Settings"
        component={SettingsScreen}
        options={{
          title: 'Settings',
          tabBarLabel: 'Settings',
          tabBarIcon: SettingsTabIcon,
        }}
      />
    </Tabs.Navigator>
  );
}

export function RootNavigator() {
  const {status} = useAuth();

  if (status === 'booting') {
    return <ScreenState loading title="Loading Lanlu" />;
  }

  return (
    <NavigationContainer>
      <Stack.Navigator>
        {status === 'authenticated' ? (
          <>
            <Stack.Screen
              name="Main"
              component={MainTabs}
              options={{headerShown: false}}
            />
            <Stack.Screen
              name="ArchiveDetail"
              component={ArchiveDetailScreen}
              options={{title: 'Archive'}}
            />
            <Stack.Screen
              name="Reader"
              component={ReaderScreen}
              options={{headerShown: false}}
            />
          </>
        ) : status === 'login' ? (
          <Stack.Screen
            name="Login"
            component={LoginScreen}
            options={{headerShown: false}}
          />
        ) : (
          <>
            <Stack.Screen
              name="ServerList"
              component={ServerListScreen}
              options={{headerShown: false}}
            />
            <Stack.Screen
              name="AddServer"
              component={AddServerScreen}
              options={{title: 'Server'}}
            />
          </>
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}
