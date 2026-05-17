import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {NavigationContainer, createNavigationContainerRef, useNavigationState} from '@react-navigation/native';
import {
  createBottomTabNavigator,
  type BottomTabBarButtonProps,
} from '@react-navigation/bottom-tabs';
import {createNativeStackNavigator} from '@react-navigation/native-stack';
import {Animated, PanResponder, Pressable, StyleSheet, Text, TouchableOpacity, View} from 'react-native';
import {enableScreens} from 'react-native-screens';
import {useSafeAreaInsets} from 'react-native-safe-area-context';
import {BlurView} from '@sbaiahmed1/react-native-blur';
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
const TAB_NAMES = ['Home', 'Favorites', 'Settings'];
const Tabs = createBottomTabNavigator<MainTabParamList>();
const navigationRef = createNavigationContainerRef<RootStackParamList>();
const contentSlideAnim = new Animated.Value(0);

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
  const insets = useSafeAreaInsets();
  const activeTab = useNavigationState(state => {
    const mainRoute = state.routes.find(r => r.name === 'Main');
    return (mainRoute?.state as any)?.index ?? 0;
  });

  const styles = useMemo(
    () =>
      StyleSheet.create({
        tabBar: {
          backgroundColor: 'transparent',
          borderTopColor: colors.border,
          borderTopWidth: StyleSheet.hairlineWidth,
          bottom: 0,
          flexDirection: 'row',
          left: 0,
          position: 'absolute',
          paddingTop: 8,
          right: 0,
        },
        tabItem: {
          alignItems: 'center',
          flex: 1,
          gap: 4,
          justifyContent: 'center',
          paddingBottom: 8,
        },
        tabLabel: {
          fontSize: 10,
          fontWeight: '600',
        },
      }),
    [colors],
  );

  const handleTabPress = useCallback((index: number) => {
    if (index === activeTab) return;
    navigationRef.navigate('Main' as never, {screen: TAB_NAMES[index]} as never);
  }, [activeTab]);

  const tabsContent = (
    <Tabs.Navigator
      tabBar={() => null}
      screenOptions={{headerShown: false}}>
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

  return (
    <View style={{flex: 1}}>
      <Animated.View style={{flex: 1, transform: [{translateX: contentSlideAnim}]}}>
        {tabsContent}
      </Animated.View>
      <View style={[styles.tabBar, {paddingBottom: insets.bottom}]}>
        <BlurTabBarBackground />
        {TAB_NAMES.map((name, index) => (
          <Pressable
            key={name}
            onPress={() => handleTabPress(index)}
            style={styles.tabItem}>
            {index === 0 && <Home color={index === activeTab ? colors.primary : colors.textMuted} size={24} />}
            {index === 1 && <Heart color={index === activeTab ? colors.primary : colors.textMuted} size={24} />}
            {index === 2 && <Settings color={index === activeTab ? colors.primary : colors.textMuted} size={24} />}
            <Text style={[styles.tabLabel, {color: index === activeTab ? colors.primary : colors.textMuted}]}>
              {index === 0 ? t('tabs.home') : index === 1 ? t('tabs.favorites') : t('tabs.settings')}
            </Text>
          </Pressable>
        ))}
      </View>
    </View>
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

  const panResponder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => false,
      onMoveShouldSetPanResponder: (_, gs) => {
        const route = currentRouteNameRef.current;
        if (!TAB_NAMES.includes(route ?? '')) return false;
        return Math.abs(gs.dx) > Math.abs(gs.dy) * 2 && Math.abs(gs.dx) > 15;
      },
      onPanResponderMove: (_, gs) => {
        const route = currentRouteNameRef.current;
        const currentIdx = TAB_NAMES.indexOf(route ?? '');
        if (route === 'Home' && gs.dx > 0) return;
        if ((gs.dx > 0 && currentIdx <= 0) || (gs.dx < 0 && currentIdx >= TAB_NAMES.length - 1)) return;
        contentSlideAnim.setValue(Math.max(-120, Math.min(120, gs.dx)));
      },
      onPanResponderRelease: (_, gs) => {
        const route = currentRouteNameRef.current;
        const currentIndex = TAB_NAMES.indexOf(route ?? '');
        if (currentIndex === -1) return;

        if (route === 'Home' && gs.dx > 50) {
          contentSlideAnim.setValue(0);
          setSidebarOpen(true);
          return;
        }

        if (Math.abs(gs.dx) < 60) {
          Animated.spring(contentSlideAnim, {
            toValue: 0,
            useNativeDriver: true,
          }).start();
          return;
        }

        const targetIdx = gs.dx > 0 ? currentIndex - 1 : currentIndex + 1;
        if (targetIdx < 0 || targetIdx >= TAB_NAMES.length) {
          Animated.spring(contentSlideAnim, {toValue: 0, useNativeDriver: true}).start();
          return;
        }

        const targetTab = TAB_NAMES[targetIdx];
        const direction = gs.dx > 0 ? 1 : -1;

        Animated.timing(contentSlideAnim, {
          toValue: direction * 500,
          duration: 180,
          useNativeDriver: true,
        }).start(() => {
          navigationRef.navigate('Main' as never, {screen: targetTab} as never);
          contentSlideAnim.setValue(-direction * 500);
          Animated.timing(contentSlideAnim, {
            toValue: 0,
            duration: 180,
            useNativeDriver: true,
          }).start();
        });
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
