import 'react-native-gesture-handler';

/**
 * @format
 */

import { AppRegistry } from 'react-native';
import App from './App';
import { name as appName } from './app.json';
import { installErrorBridge } from './src/debug/errorBridge';

installErrorBridge();

AppRegistry.registerComponent(appName, () => App);
