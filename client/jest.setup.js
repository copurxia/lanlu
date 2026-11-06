/* global jest */

import 'react-native-gesture-handler/jestSetup';

// Reanimated 4.6+ consumer Jest support is broken: the shipped mock imports the
// real entry point, which initializes the native worklets module. Keep a small
// JS-only mock until react-native-reanimated/jest/resolver ships upstream.
jest.mock('react-native-reanimated', () => {
  const React = require('react');
  const {View, Text, ScrollView, Image} = require('react-native');
  const unwrap = value =>
    value && typeof value === 'object' && 'value' in value ? value.value : value;
  const Animated = {
    View,
    Text,
    ScrollView,
    Image,
    createAnimatedComponent: component => component,
  };
  const easing = value => value;
  return {
    __esModule: true,
    ...Animated,
    default: Animated,
    useSharedValue: initial => React.useRef({value: initial}).current,
    useAnimatedStyle: factory => factory(),
    useAnimatedReaction: () => undefined,
    useDerivedValue: factory => ({value: factory()}),
    useAnimatedRef: () => React.createRef(),
    useAnimatedScrollHandler: () => () => undefined,
    withTiming: unwrap,
    withSpring: unwrap,
    withRepeat: unwrap,
    withDelay: (_delay, value) => unwrap(value),
    cancelAnimation: () => undefined,
    runOnJS: fn => fn,
    runOnUI: fn => fn,
    Easing: {
      linear: easing,
      ease: easing,
      quad: easing,
      cubic: easing,
      bezier: () => easing,
      in: easing,
      out: easing,
      inOut: easing,
    },
  };
});

jest.mock('@gorhom/bottom-sheet', () => {
  const React = require('react');
  const {View} = require('react-native');
  const BottomSheetModal = React.forwardRef((props, ref) => {
    React.useImperativeHandle(ref, () => ({
      present: jest.fn(),
      dismiss: jest.fn(),
      close: jest.fn(),
      snapToIndex: jest.fn(),
    }));
    return React.createElement(View, props, props.children);
  });
  return {
    __esModule: true,
    BottomSheetModal,
    BottomSheetModalProvider: ({children}) => children,
    BottomSheetView: View,
    BottomSheetBackdrop: () => null,
  };
});

jest.mock('@react-native-async-storage/async-storage', () => {
  const store = new Map();
  return {
    __esModule: true,
    default: {
      getItem: jest.fn(key => Promise.resolve(store.get(key) ?? null)),
      setItem: jest.fn((key, value) => {
        store.set(key, value);
        return Promise.resolve();
      }),
      removeItem: jest.fn(key => {
        store.delete(key);
        return Promise.resolve();
      }),
      multiGet: jest.fn(keys =>
        Promise.resolve(keys.map(key => [key, store.get(key) ?? null])),
      ),
      multiSet: jest.fn(entries => {
        entries.forEach(([key, value]) => store.set(key, value));
        return Promise.resolve();
      }),
      multiRemove: jest.fn(keys => {
        keys.forEach(key => store.delete(key));
        return Promise.resolve();
      }),
      clear: jest.fn(() => {
        store.clear();
        return Promise.resolve();
      }),
    },
  };
});

jest.mock('react-native-mmkv', () => {
  const stores = new Map();
  return {
    createMMKV: jest.fn().mockImplementation(({id = 'default'} = {}) => {
      if (!stores.has(id)) stores.set(id, new Map());
      const store = stores.get(id);
      return {
        getString: jest.fn(key => store.get(key)),
        set: jest.fn((key, value) => {
          store.set(key, String(value));
        }),
        remove: jest.fn(key => {
          const deleted = store.has(key);
          store.delete(key);
          return deleted;
        }),
      };
    }),
  };
});

jest.mock('react-native-keychain', () => ({
  ACCESSIBLE: {
    WHEN_UNLOCKED_THIS_DEVICE_ONLY: 'WHEN_UNLOCKED_THIS_DEVICE_ONLY',
  },
  getGenericPassword: jest.fn(() => Promise.resolve(false)),
  setGenericPassword: jest.fn(() => Promise.resolve(true)),
  resetGenericPassword: jest.fn(() => Promise.resolve(true)),
}));

jest.mock('react-native-webview', () => {
  const React = require('react');
  const {View} = require('react-native');
  return {WebView: props => React.createElement(View, props)};
});

jest.mock('@d11/react-native-fast-image', () => {
  const React = require('react');
  const {Image} = require('react-native');
  const FastImage = props => React.createElement(Image, props);

  FastImage.resizeMode = {
    contain: 'contain',
    cover: 'cover',
    stretch: 'stretch',
    center: 'center',
  };
  FastImage.priority = {
    low: 'low',
    normal: 'normal',
    high: 'high',
  };
  FastImage.cacheControl = {
    immutable: 'immutable',
    web: 'web',
    cacheOnly: 'cacheOnly',
  };
  FastImage.transition = {
    fade: 'fade',
    none: 'none',
  };
  FastImage.preload = jest.fn();
  FastImage.clearMemoryCache = jest.fn(() => Promise.resolve());
  FastImage.clearDiskCache = jest.fn(() => Promise.resolve());

  return FastImage;
});

jest.mock('react-native-vlc-media-player', () => {
  const React = require('react');
  const {View} = require('react-native');
  const VLCPlayer = React.forwardRef((props, ref) => {
    React.useImperativeHandle(ref, () => ({
      seek: jest.fn(),
      stopPlayer: jest.fn(),
    }));
    return React.createElement(View, props);
  });
  return {VLCPlayer, VlCPlayerView: VLCPlayer};
});

jest.mock('@react-native-documents/picker', () => ({
  pick: jest.fn(() => Promise.resolve([])),
  types: {},
  isErrorWithCode: jest.fn(() => false),
  errorCodes: {OPERATION_CANCELED: 'OPERATION_CANCELED'},
}));

jest.mock('react-native-notify-kit', () => {
  const notifee = {
    createChannel: jest.fn(() => Promise.resolve()),
    displayNotification: jest.fn(() => Promise.resolve('notification-id')),
    cancelNotification: jest.fn(() => Promise.resolve()),
    requestPermission: jest.fn(() => Promise.resolve({authorizationStatus: 1})),
  };
  return {
    __esModule: true,
    default: notifee,
    AndroidImportance: {LOW: 2, DEFAULT: 3, HIGH: 4},
  };
});

jest.mock('react-native-sse', () => {
  class EventSource {
    addEventListener() {}
    removeEventListener() {}
    close() {}
    open() {}
  }
  return {__esModule: true, default: EventSource};
});

jest.mock('react-native-passkey', () => ({
  Passkey: {
    isSupported: jest.fn(() => false),
    create: jest.fn(),
    get: jest.fn(),
  },
}));

jest.mock('react-native-image-picker', () => ({
  launchImageLibrary: jest.fn(),
  launchCamera: jest.fn(),
}));

jest.mock('@sbaiahmed1/react-native-blur', () => {
  const React = require('react');
  const {View} = require('react-native');
  const BlurView = React.forwardRef((props, ref) =>
    React.createElement(View, {...props, ref}),
  );
  return {__esModule: true, BlurView, default: BlurView};
});

jest.mock('react-native-qrcode-svg', () => {
  const React = require('react');
  const {View} = require('react-native');
  return {__esModule: true, default: props => React.createElement(View, props)};
});

jest.mock('@react-native-community/datetimepicker', () => {
  const React = require('react');
  const {View} = require('react-native');
  return {__esModule: true, default: props => React.createElement(View, props)};
});
