import React from 'react';
import {NavigationContainer} from '@react-navigation/native';
import {
  createBottomTabNavigator,
  type BottomTabBarButtonProps,
} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {Pressable, StyleSheet} from 'react-native';
import {enableScreens} from 'react-native-screens';
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
import {TankoubonDetailScreen} from '../screens/TankoubonDetailScreen';
import {useI18n} from '../i18n';
import {colors} from '../theme/colors';
import type {MainTabParamList, RootStackParamList} from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<MainTabParamList>();

enableScreens(true);

function HomeTabIcon({color, size}: {color: string; size: number}) {
  return <Home color={color} size={size} />;
}

function FavoritesTabIcon({color, size}: {color: string; size: number}) {
  return <Heart color={color} size={size} />;
}

function SettingsTabIcon({color, size}: {color: string; size: number}) {
  return <Settings color={color} size={size} />;
}

function StaticTabButton({
  children,
  style,
  ...props
}: BottomTabBarButtonProps) {
  return (
    <Pressable {...props} android_ripple={{color: 'transparent'}} style={style}>
      {children}
    </Pressable>
  );
}

function MainTabs() {
  const {t} = useI18n();
  return (
    <Tabs.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarButton: StaticTabButton,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarStyle: styles.tabBar,
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

const styles = StyleSheet.create({
  tabBar: {
    backgroundColor: colors.surface,
    borderTopColor: colors.border,
    borderTopWidth: StyleSheet.hairlineWidth,
    elevation: 0,
    shadowOpacity: 0,
  },
});

export function RootNavigator() {
  const {status} = useAuth();
  const {t} = useI18n();

  if (status === 'booting') {
    return <ScreenState loading title={t('common.loading')} />;
  }

  return (
    <NavigationContainer>
      <Stack.Navigator
        screenOptions={{
          animation: 'slide_from_right',
          contentStyle: {backgroundColor: colors.background},
        }}>
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
              name="TankoubonDetail"
              component={TankoubonDetailScreen}
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
