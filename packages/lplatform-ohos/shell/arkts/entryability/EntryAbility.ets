import { abilityAccessCtrl, AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { inputMethod } from '@kit.IMEKit';
import pointer from "@ohos.multimodalInput.pointer"
import shell from 'libmain.so';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // P5：页面加载改由我们自己做（原来藏在 SDL 的 provideArkTSObjects 里）。
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'LANLU-SHELL', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'LANLU-SHELL', '%{public}s', 'loadContent ok');
    });
  }

  // LWP（计划 §7）：前后台切换通知引擎。LANLU_LWP 未开时是空操作。
  // LWP：把系统事实（语言/字体目录/家目录/API 级别）下发给引擎，取代引擎里的环境变量探测。
  // 时区留空（由 C 侧后续用 OH_TimeService 补），引擎会回退到系统默认。
  private sendLwpSystemInfo(): void {
    try {
      let lang = 'zh-Hans';
      try { lang = i18n.System.getSystemLanguage(); } catch (e) {}
      let home = '';
      try { home = `${getContext(this).filesDir}`; } catch (e) {}
      try { shell.lwpSystemInfo('', lang, '/system/fonts', home, 26); } catch (e) {}
    } catch (e2) {}
  }

  onForeground(): void {
    try { this.sendLwpSystemInfo(); } catch (e) {}
    try { shell.lwpAppResumed(); } catch (e) {}
    try { shell.lwpWindowPump(); } catch (e) {}
  }

  onBackground(): void {
    try { shell.lwpAppPaused(); } catch (e) {}
  }

  // 调试后门门禁：把「本包是否可调试」告诉引擎（Cangjie 侧据此决定是否读 lanlu_env.txt）。
  // release 包 appInfo.debug=false，注入文件的通道即失效（计划 §11 风险记录）。
  private sendDebuggableFlag(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const dbg: boolean = info.appInfo.debug === true;
      shell.setEnv('LANLU_DEBUGGABLE', dbg ? '1' : '0');
      hilog.info(DOMAIN, 'LANLU-SHELL', 'debuggable=%{public}s', dbg ? 'true' : 'false');
    } catch (e) {
      // 取不到就按不可调试处理（安全默认）
      try { shell.setEnv('LANLU_DEBUGGABLE', '0'); } catch (e2) {}
    }
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.sendDebuggableFlag();
    hilog.info(DOMAIN, 'LANLU-SHELL', '%{public}s', 'entryability onCreate (P5: engine starts from shell.startEngine)');
    // 启动参数 → 引擎环境变量（`aa start ... --ps lanlu.env.KEY value`）。
    // 必须在引擎加载前完成（onCreate 早于页面 XComponent 创建）；无参数时无副作用。
    // 用途：联调/自动化驱动引擎，例如 LANLU_BENCH_ARCID 运行播放基准。
    try {
      const params: Record<string, Object> = want.parameters ?? {};
      const keys: string[] = Object.keys(params);
      for (const key of keys) {
        if (key.startsWith('lanlu.env.')) {
          const name: string = key.substring('lanlu.env.'.length);
          const value: string = params[key].toString();
          shell.setEnv(name, value);
          hilog.info(DOMAIN, 'LANLU-SHELL', 'env %{public}s=%{public}s', name, value);
        }
      }
    } catch (err) {
      hilog.warn(DOMAIN, 'LANLU-SHELL', 'want env bridge failed: %{public}s', (err as Error).message);
    }
    // 联调开关透传给页面（页面侧无法直接读 native env）
    try {
      const p2: Record<string, Object> = want.parameters ?? {};
      const v = p2['lanlu.env.LANLU_PROBE_SNAPSHOT'];
      AppStorage.setOrCreate<boolean>('lanluProbeSnap', v !== undefined && v.toString() === '1');
      const vR = p2['lanlu.env.LANLU_PROBE_SHELL_RESIZE'];
      AppStorage.setOrCreate<boolean>('lanluProbeShellResize', vR !== undefined && vR.toString() === '1');
      const vN = p2['lanlu.env.LANLU_SHELL_NO_VSYNC'];
      AppStorage.setOrCreate<boolean>('lanluNoVsync', vN !== undefined && vN.toString() === '1');
      // 关窗链路探针：模拟"系统关闭钮"调用 lwpSendCloseRequest（与 windowWillClose 同一条路径），
      // 用于自动验证 close_request -> 引擎退出（docs/lwindow-title-buttons-plan.md）。
      const vC = p2['lanlu.env.LANLU_PROBE_CLOSE'];
      AppStorage.setOrCreate<boolean>('lanluProbeClose', vC !== undefined && vC.toString() === '1');
    } catch (eP) {}
    // P5：不再把 ArkTS 对象交给 SDL（引擎由 shell.startEngine() 启动，窗口/输入走 L 层）
  }
}
