import type {ImageStyle as ReactNativeImageStyle} from 'react-native';

declare module '@d11/react-native-fast-image' {
  // @d11/react-native-fast-image@8.13 still imports FlexStyle in its declaration,
  // but React Native 0.88 no longer exports that alias. Merge the current image
  // style so width/height and the other layout props keep type-checking.
  interface ImageStyle extends ReactNativeImageStyle {}
}
