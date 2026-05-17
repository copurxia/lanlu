import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {NavigationContainer, createNavigationContainerRef} from '@react-navigation/native';
import {
  createBottomTabNavigator,
  type BottomTabBarButtonProps,
} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {PanResponder, Pressable, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {enableScreens} from 'react-native-screens';
import {Heart, Home, Settings} from 'lucide-react-native';

import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {Sidebar} from '../components/Sidebar';
import {fetchCategories, fetchSmartFilters} from '../api/lanlu';
import {useOfflineFeedStore} from '../stores/offlineFeedStore';
import {AccountSecurityScreen} from '../screens/AccountSecurityScreen';
import {AddServerScreen} from '../screens/AddServerScreen';
import {ArchiveDetailScreen} from '../screens/ArchiveDetailScreen';
import {CacheSettingsScreen} from '../screens/CacheSettingsScreen';
import {CategorySettingsScreen} from '../screens/CategorySettingsScreen';
import {CronSettingsScreen} from '../screens/CronSettingsScreen';
import {DiagnosticsSettingsScreen} from '../screens/DiagnosticsSettingsScreen';
import {FavoritesScreen} from '../screens/FavoritesScreen';
import {HomeScreen} from '../screens/HomeScreen';
import {LanguageSettingsScreen} from '../screens/LanguageSettingsScreen';
import {LoginScreen} from '../screens/LoginScreen';
import {PluginSettingsScreen} from '../screens/PluginSettingsScreen';
import {ReaderScreen} from '../screens/ReaderScreen';
import {ServerListScreen} from '../screens/ServerListScreen';
import {SettingsScreen} from '../screens/SettingsScreen';
import {SmartFilterSettingsScreen} from '../screens/SmartFilterSettingsScreen';
import {StatsSettingsScreen} from '../screens/StatsSettingsScreen';
import {SystemSettingsScreen} from '../screens/SystemSettingsScreen';
import {TagSettingsScreen} from '../screens/TagSettingsScreen';
import {TankoubonDetailScreen} from '../screens/TankoubonDetailScreen';
import {TaskSettingsScreen} from '../screens/TaskSettingsScreen';
import {ThemeSettingsScreen} from '../screens/ThemeSettingsScreen';
import {UserSettingsScreen} from '../screens/UserSettingsScreen';
import {useI18n} from '../i18n';
import {useTheme} from '../theme/ThemeContext';
import type {MainTabParamList, RootStackParamList} from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<MainTabParamList>();
const navigationRef = createNavigationContainerRef<RootStackParamList>();

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
  const {colors} = useTheme();
  const styles = useMemo(
    () =>
      StyleSheet.create({
        tabBar: {
          backgroundColor: colors.surface,
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          elevation: 0,
          shadowOpacity: 0,
        },
      }),
    [colors],
  );
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

export function RootNavigator() {
  const {status, isOffline, reconnect, activeServer, showServerList, signOut} = useAuth();
  const {t} = useI18n();
  const {colors} = useTheme();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarCategories, setSidebarCategories] = useState<any[]>([]);
  const [sidebarSmartFilters, setSidebarSmartFilters] = useState<any[]>([]);
  const currentRouteNameRef = useRef<string | null>(null);
  const getCachedFeed = useOfflineFeedStore(s => s.getCachedFeed);
  const serverId = activeServer?.id || '';

  useEffect(() => {
    if (isOffline && serverId) {
      const cached = getCachedFeed(serverId, 'chips');
      if (cached) {
        setSidebarCategories(cached.categories);
        setSidebarSmartFilters(cached.smartFilters || []);
        return;
      }
    }
    Promise.all([
      fetchCategories(),
      fetchSmartFilters(),
    ])
      .then(([cats, filters]) => {
        setSidebarCategories(cats);
        setSidebarSmartFilters(filters);
      })
      .catch(() => {});
  }, [isOffline, serverId, getCachedFeed]);

  const closeSidebar = useCallback(() => setSidebarOpen(false), []);
  const handleNavStateChange = useCallback(() => {
    const route = navigationRef.getCurrentRoute();
    currentRouteNameRef.current = route?.name ?? null;
  }, []);

  const edgePanResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onMoveShouldSetPanResponder: (_, gs) =>
        currentRouteNameRef.current === 'Home' && gs.dx > 15 && gs.moveX > 40,
      onPanResponderRelease: (_, gs) => {
        if (currentRouteNameRef.current === 'Home' && gs.dx > 50) setSidebarOpen(true);
      },
    }),
  ).current;

  const bannerStyles = useMemo(
    () =>
      StyleSheet.create({
        wrapper: {
          flex: 1,
        },
        container: {
          backgroundColor: '#f0a020',
          flexDirection: 'row',
          alignItems: 'center',
          justifyContent: 'center',
          paddingTop: 50,
          paddingBottom: 6,
          paddingHorizontal: 16,
        },
        text: {
          color: '#fff',
          fontSize: 13,
          fontWeight: '600',
        },
        button: {
          marginLeft: 12,
          paddingHorizontal: 10,
          paddingVertical: 4,
          borderRadius: 4,
          borderWidth: 1,
          borderColor: '#fff',
        },
        buttonText: {
          color: '#fff',
          fontSize: 12,
          fontWeight: '700',
        },
      }),
    [],
  );

  if (status === 'booting') {
    return <ScreenState loading title={t('common.loading')} />;
  }

  return (
    <View style={bannerStyles.wrapper} {...edgePanResponder.panHandlers}>
      {isOffline && status === 'authenticated' ? (
        <View style={bannerStyles.container}>
          <Text style={bannerStyles.text}>{t('common.offline')}</Text>
          <TouchableOpacity
            style={bannerStyles.button}
            onPress={() => {
              reconnect().catch(() => undefined);
            }}>
            <Text style={bannerStyles.buttonText}>{t('common.reconnect')}</Text>
          </TouchableOpacity>
        </View>
      ) : null}
      <NavigationContainer ref={navigationRef} onReady={handleNavStateChange} onStateChange={handleNavStateChange}>
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
                name="AccountSecurity"
                component={AccountSecurityScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="ThemeSettings"
                component={ThemeSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="LanguageSettings"
                component={LanguageSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="DiagnosticsSettings"
                component={DiagnosticsSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CacheSettings"
                component={CacheSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CategorySettings"
                component={CategorySettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="TagSettings"
                component={TagSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="SmartFilterSettings"
                component={SmartFilterSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="UserSettings"
                component={UserSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="SystemSettings"
                component={SystemSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="TaskSettings"
                component={TaskSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CronSettings"
                component={CronSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="PluginSettings"
                component={PluginSettingsScreen}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="StatsSettings"
                component={StatsSettingsScreen}
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
      {status === 'authenticated' ? (
        <Sidebar
          open={sidebarOpen}
          onClose={closeSidebar}
          categories={sidebarCategories}
          smartFilters={sidebarSmartFilters}
          selectedCategoryId={null}
          onSelectCategory={() => {}}
          serverName={activeServer?.name}
          onSwitchServer={() => showServerList()}
          onSignOut={() => signOut()}
        />
      ) : null}
    </View>
  );
}
