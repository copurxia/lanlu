import type {Archive, Tankoubon} from '../types/api';
import type {LanluServer} from '../storage/servers';

export type RootStackParamList = {
  ServerList: undefined;
  AddServer: {server?: LanluServer} | undefined;
  Login: undefined;
  Main: undefined;
  TankoubonDetail: {tankoubonId: string; tankoubon?: Tankoubon};
  ArchiveDetail: {archiveId: string; archive?: Archive};
  Reader: {
    archiveId: string;
    initialPage?: number;
    tankoubonId?: string;
    children?: string[];
    childIndex?: number;
  };
};

export type MainTabParamList = {
  Home: undefined;
  Favorites: undefined;
  Settings: undefined;
};
