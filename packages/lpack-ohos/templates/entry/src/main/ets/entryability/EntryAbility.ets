import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'CJPROBE';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
  }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // setWindowDecorVisible 必须在 loadContent 生效之后调用（否则 1300002）
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) { hilog.error(DOMAIN, TAG, 'loadContent fail %{public}s', JSON.stringify(err)); return; }
      try {
        const win = windowStage.getMainWindowSync();
        win.setWindowDecorVisible(false);   // 只隐藏标题栏，保持普通窗口
        hilog.info(DOMAIN, TAG, 'title bar hidden (decor=false)');
      } catch (e) { hilog.error(DOMAIN, TAG, 'hide decor fail %{public}s', JSON.stringify(e)); }
    });
  }
  onDestroy(): void {}
  onWindowStageDestroy(): void {}
  onForeground(): void {}
  onBackground(): void {}
}
