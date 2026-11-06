import React, {lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {
  DarkTheme,
  DefaultTheme,
  NavigationContainer,
  createNavigationContainerRef,
  type Theme,
} from '@react-navigation/native';
import {createBottomTabNavigator} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {PanResponder, Platform, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {enableScreens} from 'react-native-screens';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {BlurView} from '@sbaiahmed1/react-native-blur';
import {Heart, Home, Settings, Upload} from 'lucide-react-native';

import {useAuth} from '../auth/AuthContext';
import {ScreenState} from '../components/ScreenState';
import {Sidebar} from '../components/Sidebar';
import {fetchCategoriesShared, fetchSmartFiltersShared} from '../api/catalog';
import {useOfflineFeedStore} from '../stores/offlineFeedStore';
import {AddServerScreen} from '../screens/AddServerScreen';
import {HomeScreen} from '../screens/HomeScreen';
import {LoginScreen} from '../screens/LoginScreen';
import {ServerListScreen} from '../screens/ServerListScreen';
import {useI18n} from '../i18n';
import {useTheme} from '../theme/ThemeContext';
import {perfMark} from '../perf/perf';
import type {MainTabParamList, RootStackParamList} from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Tabs = createBottomTabNavigator<MainTabParamList>();
const navigationRef = createNavigationContainerRef<RootStackParamList>();

enableScreens(true);

function lazyScreen(loader: () => Promise<any>, exportName: string) {
  const Component = lazy(async () => ({default: (await loader())[exportName]}));
  return function LazyScreenRoute(props: any) {
    return (
      <Suspense fallback={<ScreenState loading />}>
        <Component {...props} />
      </Suspense>
    );
  };
}

const FavoritesRoute = lazyScreen(() => import('../screens/FavoritesScreen'), 'FavoritesScreen');
const SettingsRoute = lazyScreen(() => import('../screens/SettingsScreen'), 'SettingsScreen');
const ThemeSettingsRoute = lazyScreen(() => import('../screens/ThemeSettingsScreen'), 'ThemeSettingsScreen');
const LanguageSettingsRoute = lazyScreen(() => import('../screens/LanguageSettingsScreen'), 'LanguageSettingsScreen');
const DiagnosticsSettingsRoute = lazyScreen(() => import('../screens/DiagnosticsSettingsScreen'), 'DiagnosticsSettingsScreen');
const CacheSettingsRoute = lazyScreen(() => import('../screens/CacheSettingsScreen'), 'CacheSettingsScreen');
const CategorySettingsRoute = lazyScreen(() => import('../screens/CategorySettingsScreen'), 'CategorySettingsScreen');
const TagSettingsRoute = lazyScreen(() => import('../screens/TagSettingsScreen'), 'TagSettingsScreen');
const SmartFilterSettingsRoute = lazyScreen(() => import('../screens/SmartFilterSettingsScreen'), 'SmartFilterSettingsScreen');
const UserSettingsRoute = lazyScreen(() => import('../screens/UserSettingsScreen'), 'UserSettingsScreen');
const SystemSettingsRoute = lazyScreen(() => import('../screens/SystemSettingsScreen'), 'SystemSettingsScreen');
const TaskSettingsRoute = lazyScreen(() => import('../screens/TaskSettingsScreen'), 'TaskSettingsScreen');
const CronSettingsRoute = lazyScreen(() => import('../screens/CronSettingsScreen'), 'CronSettingsScreen');
const PluginSettingsRoute = lazyScreen(() => import('../screens/PluginSettingsScreen'), 'PluginSettingsScreen');
const StatsSettingsRoute = lazyScreen(() => import('../screens/StatsSettingsScreen'), 'StatsSettingsScreen');

// Keep the heavy, non-initial screens out of the startup module graph. Their
// code (ReaderShell, VLC, file pickers, admin panels) is evaluated on first use.
const LazyArchiveDetailScreen = lazy(() =>
  import('../screens/ArchiveDetailScreen').then(m => ({default: m.ArchiveDetailScreen})),
);
const LazyTankoubonDetailScreen = lazy(() =>
  import('../screens/TankoubonDetailScreen').then(m => ({default: m.TankoubonDetailScreen})),
);
const LazyReaderScreen = lazy(() =>
  import('../screens/ReaderScreen').then(m => ({default: m.ReaderScreen})),
);
const LazyAccountSecurityScreen = lazy(() =>
  import('../screens/AccountSecurityScreen').then(m => ({default: m.AccountSecurityScreen})),
);
const LazyUploadScreen = lazy(() =>
  import('../screens/UploadScreen').then(m => ({default: m.UploadScreen})),
);

function ArchiveDetailRoute(props: any) {
  return (
    <Suspense fallback={<ScreenState loading />}>
      <LazyArchiveDetailScreen {...props} />
    </Suspense>
  );
}

function TankoubonDetailRoute(props: any) {
  return (
    <Suspense fallback={<ScreenState loading />}>
      <LazyTankoubonDetailScreen {...props} />
    </Suspense>
  );
}

function ReaderRoute(props: any) {
  return (
    <Suspense fallback={<ScreenState loading />}>
      <LazyReaderScreen {...props} />
    </Suspense>
  );
}

function AccountSecurityRoute(props: any) {
  return (
    <Suspense fallback={<ScreenState loading />}>
      <LazyAccountSecurityScreen {...props} />
    </Suspense>
  );
}

function UploadRoute(props: any) {
  return (
    <Suspense fallback={<ScreenState loading />}>
      <LazyUploadScreen {...props} />
    </Suspense>
  );
}

function HomeTabIcon({color, size}: {color: string; size: number}) {
  return <Home color={color} size={size} />;
}

function FavoritesTabIcon({color, size}: {color: string; size: number}) {
  return <Heart color={color} size={size} />;
}

function SettingsTabIcon({color, size}: {color: string; size: number}) {
  return <Settings color={color} size={size} />;
}

function UploadTabIcon({color, size}: {color: string; size: number}) {
  return <Upload color={color} size={size} />;
}

function BlurTabBarBackground() {
  const {effectiveScheme, colors} = useTheme();
  return (
    <View style={StyleSheet.absoluteFill}>
      <BlurView
        blurType={effectiveScheme === 'dark' ? 'dark' : 'light'}
        blurAmount={24}
        style={StyleSheet.absoluteFill}
      />
      <View style={[StyleSheet.absoluteFill, {backgroundColor: colors.surface + '80'}]} />
    </View>
  );
}

function MainTabs() {
  const {t} = useI18n();
  const {colors} = useTheme();
  const {user} = useAuth();

  return (
    <Tabs.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarBackground: BlurTabBarBackground,
        tabBarHideOnKeyboard: true,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarLabelStyle: {fontSize: 10, fontWeight: '600'},
        tabBarStyle: {
          backgroundColor: 'transparent',
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
        },
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
        component={FavoritesRoute}
        options={{
          title: t('tabs.favorites'),
          tabBarLabel: t('tabs.favorites'),
          tabBarIcon: FavoritesTabIcon,
        }}
      />
      {user?.isAdmin ? (
        <Tabs.Screen
          name="Upload"
          component={UploadRoute}
          options={{
            title: t('tabs.upload'),
            tabBarLabel: t('tabs.upload'),
            tabBarIcon: UploadTabIcon,
          }}
        />
      ) : null}
      <Tabs.Screen
        name="Settings"
        component={SettingsRoute}
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
  const {colors, effectiveScheme} = useTheme();
  const insets = useSafeAreaInsets();
  const [activeRouteName, setActiveRouteName] = useState<string | null>(null);
  const navigationTheme = useMemo<Theme>(() => {
    const base = effectiveScheme === 'dark' ? DarkTheme : DefaultTheme;
    return {
      ...base,
      colors: {
        ...base.colors,
        primary: colors.primary,
        background: colors.background,
        card: colors.surface,
        text: colors.text,
        border: colors.border,
        notification: colors.danger,
      },
    };
  }, [colors, effectiveScheme]);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [sidebarCategories, setSidebarCategories] = useState<any[]>([]);
  const [sidebarSmartFilters, setSidebarSmartFilters] = useState<any[]>([]);
  const currentRouteNameRef = useRef<string | null>(null);
  const sidebarOpenRef = useRef(false);
  const navReadyRef = useRef(false);
  const bootingMarkedRef = useRef(false);
  const getCachedFeed = useOfflineFeedStore(s => s.getCachedFeed);
  const serverId = activeServer?.id || '';

  useEffect(() => {
    sidebarOpenRef.current = sidebarOpen;
  }, [sidebarOpen]);

  useEffect(() => {
    if (status === 'authenticated' && !navReadyRef.current) {
      navReadyRef.current = true;
      perfMark('nav.authenticated');
    }
  }, [status]);

  useEffect(() => {
    if (!sidebarOpen || status !== 'authenticated') {
      return;
    }
    if (serverId) {
      const cached = getCachedFeed(serverId, 'chips');
      if (cached) {
        setSidebarCategories(cached.categories);
        setSidebarSmartFilters(cached.smartFilters || []);
        if (isOffline) return;
      }
    }
    Promise.all([
      fetchCategoriesShared(),
      fetchSmartFiltersShared(),
    ])
      .then(([cats, filters]) => {
        setSidebarCategories(cats);
        setSidebarSmartFilters(filters);
      })
      .catch(() => {});
  }, [isOffline, serverId, sidebarOpen, status, getCachedFeed]);

  const closeSidebar = useCallback(() => setSidebarOpen(false), []);
  const handleNavStateChange = useCallback(() => {
    const route = navigationRef.getCurrentRoute();
    currentRouteNameRef.current = route?.name ?? null;
    setActiveRouteName(route?.name ?? null);
  }, []);

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onMoveShouldSetPanResponder: (_, gs) => {
        if (currentRouteNameRef.current !== 'Home') return false;
        return (
          Math.abs(gs.dx) > Math.abs(gs.dy) * 2 &&
          (sidebarOpenRef.current ? Math.abs(gs.dx) > 15 : gs.dx > 15)
        );
      },
      onPanResponderRelease: (_, gs) => {
        if (sidebarOpenRef.current) {
          if (gs.dx < -50 || gs.vx < -0.5) setSidebarOpen(false);
          return;
        }
        if (gs.dx > 50) setSidebarOpen(true);
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
    if (!bootingMarkedRef.current) {
      bootingMarkedRef.current = true;
      perfMark('nav.booting_render');
    }
    return <ScreenState loading title={t('common.loading')} />;
  }

  return (
    <View style={bannerStyles.wrapper} {...panResponder.panHandlers}>
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
      <NavigationContainer
        ref={navigationRef}
        theme={navigationTheme}
        onReady={handleNavStateChange}
        onStateChange={handleNavStateChange}>
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
                component={AccountSecurityRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="ThemeSettings"
                component={ThemeSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="LanguageSettings"
                component={LanguageSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="DiagnosticsSettings"
                component={DiagnosticsSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CacheSettings"
                component={CacheSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CategorySettings"
                component={CategorySettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="TagSettings"
                component={TagSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="SmartFilterSettings"
                component={SmartFilterSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="UserSettings"
                component={UserSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="SystemSettings"
                component={SystemSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="TaskSettings"
                component={TaskSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="CronSettings"
                component={CronSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="PluginSettings"
                component={PluginSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="StatsSettings"
                component={StatsSettingsRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="ArchiveDetail"
                component={ArchiveDetailRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="TankoubonDetail"
                component={TankoubonDetailRoute}
                options={{headerShown: false}}
              />
              <Stack.Screen
                name="Reader"
                component={ReaderRoute}
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
      {Platform.OS === 'android' && activeRouteName !== 'Reader' ? (
        <View
          pointerEvents="none"
          style={{
            backgroundColor: colors.background,
            height: insets.top,
            left: 0,
            position: 'absolute',
            right: 0,
            top: 0,
            zIndex: 999,
          }}
        />
      ) : null}
      {Platform.OS === 'android' && activeRouteName !== 'Reader' && insets.bottom > 0 ? (
        <View
          pointerEvents="none"
          style={{
            backgroundColor: colors.background,
            bottom: 0,
            height: insets.bottom,
            left: 0,
            position: 'absolute',
            right: 0,
            zIndex: 999,
          }}
        />
      ) : null}
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
