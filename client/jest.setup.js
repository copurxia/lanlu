/* global jest */

import 'react-native-gesture-handler/jestSetup';

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
      clear: jest.fn(() => {
        store.clear();
        return Promise.resolve();
      }),
    },
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
