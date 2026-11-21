import React, {useMemo} from 'react';
import {StatusBar, StyleSheet} from 'react-native';
import {GestureHandlerRootView} from 'react-native-gesture-handler';
import {BottomSheetModalProvider} from '@gorhom/bottom-sheet';
import {SafeAreaProvider} from 'react-native-safe-area-context';

import {AuthProvider} from './src/auth/AuthContext';
import {I18nProvider} from './src/i18n';
import {RootNavigator} from './src/navigation/RootNavigator';
import {perfMark} from './src/perf/perf';
import {ThemeProvider, useTheme} from './src/theme/ThemeContext';

perfMark('app.module');

let appShellMarked = false;

function AppShell() {
  const {colors, effectiveScheme} = useTheme();
  if (!appShellMarked) {
    appShellMarked = true;
    perfMark('app.shell_render');
  }
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
          barStyle={effectiveScheme === 'dark' ? 'light-content' : 'dark-content'}
        />
        <BottomSheetModalProvider>
          <I18nProvider>
            <AuthProvider>
              <RootNavigator />
            </AuthProvider>
          </I18nProvider>
        </BottomSheetModalProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}

let appFirstRenderMarked = false;

function App() {
  if (!appFirstRenderMarked) {
    appFirstRenderMarked = true;
    perfMark('app.first_render');
  }
  return (
    <ThemeProvider>
      <AppShell />
    </ThemeProvider>
  );
}

export default App;
