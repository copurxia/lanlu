import type {Archive, Tankoubon} from '../types/api';
import type {LanluServer} from '../storage/servers';

export type RootStackParamList = {
  ServerList: undefined;
  AddServer: {server?: LanluServer} | undefined;
  Login: undefined;
  Main: undefined;
  // Settings
  AccountSecurity: undefined;
  ThemeSettings: undefined;
  LanguageSettings: undefined;
  DiagnosticsSettings: undefined;
  CacheSettings: undefined;
  OverviewSettings: undefined;
  CategorySettings: undefined;
  TagSettings: undefined;
  SmartFilterSettings: undefined;
  UserSettings: undefined;
  SystemSettings: undefined;
  TaskSettings: undefined;
  CronSettings: undefined;
  PluginSettings: undefined;
  StatsSettings: undefined;
  TankoubonDetail: {tankoubonId: string; tankoubon?: Tankoubon};
  ArchiveDetail: {
    archiveId: string;
    archive?: Archive;
    tankoubonId?: string;
    children?: string[];
    childIndex?: number;
  };
  Reader: {
    archiveId: string;
    initialPage?: number;
    tankoubonId?: string;
    children?: string[];
    childIndex?: number;
    resumeCollection?: boolean;
  };
};

export type MainTabParamList = {
  Home: undefined;
  Favorites: undefined;
  Upload: undefined;
  Settings: undefined;
};
