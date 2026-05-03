import React, {useMemo} from 'react';
import {StatusBar, StyleSheet} from 'react-native';
import {GestureHandlerRootView} from 'react-native-gesture-handler';
import {SafeAreaProvider} from 'react-native-safe-area-context';

import {AuthProvider} from './src/auth/AuthContext';
import {I18nProvider} from './src/i18n';
import {RootNavigator} from './src/navigation/RootNavigator';
import {ThemeProvider, useTheme} from './src/theme/ThemeContext';

function AppShell() {
  const {colors, effectiveScheme} = useTheme();
  const styles = useMemo(
    () =>
      StyleSheet.create({
        root: {
          backgroundColor: colors.background,
          flex: 1,
        },
      }),
    [colors],
  );

  return (
    <GestureHandlerRootView style={styles.root}>
      <SafeAreaProvider>
        <StatusBar
          backgroundColor="transparent"
          barStyle={effectiveScheme === 'dark' ? 'light-content' : 'dark-content'}
          translucent
        />
        <I18nProvider>
          <AuthProvider>
            <RootNavigator />
          </AuthProvider>
        </I18nProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

function App() {
  return (
    <ThemeProvider>
      <AppShell />
    </ThemeProvider>
  );
}

export default App;
