import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {Heart, Home, Settings} from 'lucide-react-native';

import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {AddServerScreen} from '../screens/AddServerScreen';
import {ArchiveDetailScreen} from '../screens/ArchiveDetailScreen';
import {FavoritesScreen} from '../screens/FavoritesScreen';
import {HomeScreen} from '../screens/HomeScreen';
import {LoginScreen} from '../screens/LoginScreen';
import {ReaderScreen} from '../screens/ReaderScreen';
import {ServerListScreen} from '../screens/ServerListScreen';
import {SettingsScreen} from '../screens/SettingsScreen';
import {useI18n} from '../i18n';
import {colors} from '../theme/colors';
import type {MainTabParamList, RootStackParamList} from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<MainTabParamList>();

function HomeTabIcon({color, size}: {color: string; size: number}) {
  return <Home color={color} size={size} />;
}

function FavoritesTabIcon({color, size}: {color: string; size: number}) {
  return <Heart color={color} size={size} />;
}

function SettingsTabIcon({color, size}: {color: string; size: number}) {
  return <Settings color={color} size={size} />;
}

function MainTabs() {
  const {t} = useI18n();
  return (
    <Tabs.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textMuted,
      }}>
      <Tabs.Screen
        name="Home"
        component={HomeScreen}
        options={{
          title: t('tabs.home'),
          tabBarLabel: t('tabs.home'),
          tabBarIcon: HomeTabIcon,
        }}
      />
      <Tabs.Screen
        name="Favorites"
        component={FavoritesScreen}
        options={{
          title: t('tabs.favorites'),
          tabBarLabel: t('tabs.favorites'),
          tabBarIcon: FavoritesTabIcon,
        }}
      />
      <Tabs.Screen
        name="Settings"
        component={SettingsScreen}
        options={{
          title: t('tabs.settings'),
          tabBarLabel: t('tabs.settings'),
          tabBarIcon: SettingsTabIcon,
        }}
      />
    </Tabs.Navigator>
  );
}

export function RootNavigator() {
  const {status} = useAuth();
  const {t} = useI18n();

  if (status === 'booting') {
    return <ScreenState loading title={t('common.loading')} />;
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
              options={{headerShown: false}}
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
              options={{headerShown: false}}
            />
          </>
        )}
      </Stack.Navigator>
    </NavigationContainer>
  );
}
