import { window } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common, abilityAccessCtrl, PermissionRequestResult, ConfigurationConstant } from '@kit.AbilityKit';
import { componentSnapshot } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { display } from '@kit.ArkUI';
import { pointer } from '@kit.InputKit';
import shell from 'libmain.so';

const DOMAIN = 0x0000;

// System layer lives here (packages/ohos), not in the engine: the window-level
// mouse/keyboard filters need the ArkTS window id + rect, which only this page
// can read (same arrangement as horizon-ohos' shell).
// 键修饰键位掩码（与 LWP_KEY_MODIFIERS_*/SDL_KMOD_* 同值，引擎直接复用）。
class LanluKeyMods {
  static mask(event: KeyEvent): number {
    let m: number = 0;
    try {
      const g = event.getModifierKeyState;
      if (g !== undefined) {
        // ArkTS 禁止 Function.call/apply：可选方法直接调用（逐个查，命中即置位）
        if (g(['Shift'])) { m = m | 1; }
        if (g(['Ctrl'])) { m = m | 64; }
        if (g(['Alt'])) { m = m | 256; }
        if (g(['Meta'])) { m = m | 1024; }
      }
    } catch (eM) {}
    return m;
  }

  // 该键产生的文本（输入法没消费的键才会到这里）：优先 unicode，其次按 keyCode 查表。
  // OHOS 的 KeyEvent.unicode 常常是 0（只有部分场景填充），所以必须自带 US 布局表兜底，
  // 否则字母会"有键无字"（真机实测：数字进得去、字母进不去）。
  static text(event: KeyEvent, mods: number): string {
    const u: number = event.unicode ?? 0;
    if (u >= 0x20 && u !== 0x7f) {
      return String.fromCharCode(u);
    }
    const k: number = event.keyCode;
    const shift: boolean = (mods & 1) !== 0;
    if (k >= 2000 && k <= 2009) {                       // 主键盘 1..0
      const digits: string = "1234567890";
      const shifted: string = "!@#$%^&*()";
      return shift ? shifted.charAt(k - 2000) : digits.charAt(k - 2000);
    }
    if (k >= 2103 && k <= 2112) {                       // 小键盘 0..9
      return String.fromCharCode(48 + ((k - 2103 + 9) % 10));
    }
    if (k >= 2017 && k <= 2042) {                       // A..Z
      const lower: string = "abcdefghijklmnopqrstuvwxyz";
      const c: string = lower.charAt(k - 2017);
      return shift ? c.toUpperCase() : c;
    }
    if (k === 2050) { return " "; }                     // SPACE
    return '';
  }
}

// 整窗 XComponent 控制器：surface 尺寸只取 onSurfaceChanged 的 SurfaceRect（单位 px，
// 是 XComponent 真实可绘制区域）。之前用 onSizeChange（单位 vp）当 px 用，1.9 倍缩放下
// 交换链只配到约 1100×733；初始尺寸又取 windowRect（窗口≠组件），评审 W2/W3。
class LanluMainXcController extends XComponentController {
  public lastW: number = 0;
  public lastH: number = 0;
  public surfaceReady: boolean = false;

  onSurfaceCreated(surfaceId: string): void {
    console.info('[LANLU-SHELL] main surface created ' + surfaceId);
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    const w: number = Math.round(rect.surfaceWidth);
    const h: number = Math.round(rect.surfaceHeight);
    if (w <= 0 || h <= 0 || (w === this.lastW && h === this.lastH)) {
      return;
    }
    this.lastW = w;
    this.lastH = h;
    console.info('[LANLU-SHELL] main surface changed ' + w + 'x' + h + ' px');
    // surface.available 之前的尺寸变化只记录（setMainSurface 会带上最新值）
    if (this.surfaceReady) {
      try { shell.lwpSurfaceChanged(w, h); } catch (e) {}
    }
  }

  onSurfaceDestroyed(surfaceId: string): void {
    console.info('[LANLU-SHELL] main surface destroyed ' + surfaceId);
  }
}

@Entry
@Component
struct Index {
  // Text input: the OHOS SDL backend emits no SDL_EVENT_TEXT_INPUT, so attach
  // the system input method and forward committed text/editing commands to the
  // engine (libmain.so replays them as SDL events the UI layer already handles).
  private imeAttached: boolean = false;
  private imeBusy: boolean = false;
  private winId: number = -1;
  // L 层渲染器上屏自检：一块独立小 XComponent，由 lgpu(wgpu) 清屏 present，
  // 验证 "wgpu → VK_OHOS_surface → 上屏"（不影响 SDL 主表面）。
  private lgpuCtl: XComponentController = new XComponentController();
  @State private lgpuTest: boolean = false;
  // P5 预演：整窗由 lgpu 渲染（LANLU_MAIN_LGPU=1 时启用，SDL 窗口仍在下面但不再 present）
  @State private lgpuMain: boolean = false;
  // 输入链路自检：定时向 L 层事件桥注入合成指针事件（LANLU_PROBE_INPUT=1）
  private inputProbeTimer: number = -1;
  // 窗口控制通道：轮询引擎写下的命令文件并执行（minimize/maximize/restore/close）
  private windowCmdTimer: number = -1;
  private lgpuMainCtl: LanluMainXcController = new LanluMainXcController();
  private exitTimer: number = -1;
  private lwpPumpTimer: number = -1;
  private frameLogTick: number = 0;
  private lwpDialogSerial: number = 0;
  private dialogBusy: boolean = false;
  // vsync：壳用 ArkTS displaySync 的每帧回调回 frame.done（引擎据此配速）
  private vsyncObj: displaySync.DisplaySync | undefined = undefined;
  // 平台三键（docs/lwindow-title-buttons-plan.md）：最近一次事件给的矩形（vp）+
  // 已上报引擎的 px 快照（只在变化时上报，避免每 400ms 刷屏）。
  private lastTitleBtnRect: window.TitleButtonRect | undefined = undefined;
  private titleBtnReportedPx: number[] = [-1, -1, -1, -1, -1];
  // 联调：LANLU_PROBE_SHELL_RESIZE=1 时每秒真实改一次窗口尺寸（验 surface.changed 链路）
  private shellResizeTick: number = 0;
  private probeShellResize: boolean = false;
  private host: common.UIAbilityContext | undefined = undefined;

  // The engine returns when the user closes the window from the app's own
  // title bar; finish the ability so no empty window is left behind.
  private win: window.Window | undefined = undefined;
  // File dialogs: SDL's OpenHarmony backend has no picker, so the request comes
  // here. The engine gets real sandbox paths (copied from the picked uri), which
  // is what its file APIs expect. Save/folder are cancelled for now.

  // Save dialogs: the engine writes to a sandbox path we hand it, then we copy
  // the finished file to the uri the user picked (stability poll, bounded).
  // ── 对话框/抓帧的公共助手（M6 第 3 步重写：文件桥删除时一并被删，这里按调用点重建）──
  private withPickerTimeout<T>(p: Promise<T>, ms: number, tag: string): Promise<T | undefined> {
    return new Promise<T | undefined>((resolve, reject) => {
      let done = false;
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        console.error('[LANLU-SHELL] picker timeout: ' + tag);
        resolve(undefined);
      }, ms);
      p.then((v: T) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        resolve(v);
      }).catch((e: Error) => {
        if (done) return;
        done = true;
        clearTimeout(timer);
        reject(e);
      });
    });
  }

  private snapLog(msg: string): void {
    console.info('[LANLU-SHELL] snap ' + msg);
  }

  private writeWhole(path: string, data: string | ArrayBuffer): void {
    const f = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    fs.writeSync(f.fd, data);
    fs.closeSync(f);
  }

  private async pickOpenFile(): Promise<void> {
    try {
      const docPicker = new picker.DocumentViewPicker(this.host!);
      const uris = await this.withPickerTimeout(docPicker.select({ maxSelectNumber: 1 }),
        120000, 'open picker');
      if (uris === undefined || uris.length === 0) {
        this.finishDialog('');
        return;
      }
      const paths: string[] = [];
      for (let i = 0; i < uris.length; i++) {
        const dst = this.host!.cacheDir + '/pick-' + Date.now() + '-' + i;
        const src = fs.openSync(uris[i], fs.OpenMode.READ_ONLY);
        const out = fs.openSync(dst, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.copyFileSync(src.fd, out.fd);
        fs.closeSync(src);
        fs.closeSync(out);
        paths.push(dst);
      }
      this.finishDialog(paths.join('\n'));
    } catch (err) {
      console.error('[LANLU-SHELL] pickOpenFile failed: ' + JSON.stringify(err));
      this.finishDialog('');
    }
  }

  private async handleSaveDialog(): Promise<void> {
    const name = 'lanlu-export-' + Date.now();
    try {
      const uris = await this.withPickerTimeout(
        new picker.DocumentViewPicker(this.host!).save({ newFileNames: [name] }),
        120000, 'save picker');
      if (uris === undefined || uris.length === 0) {
        this.finishDialog('');
        return;
      }
      const uri = uris[0];
      const tmp = this.host!.cacheDir + '/' + name + '.part';
      this.finishDialog(tmp);
      this.watchSavedFile(tmp, uri);
    } catch (err) {
      console.error('[LANLU-SHELL] save dialog failed: ' + JSON.stringify(err));
      this.finishDialog('');
    }
  }

  private watchSavedFile(tmp: string, uri: string): void {
    let lastSize = -1;
    let stable = 0;
    let waited = 0;
    const timer = setInterval(() => {
      waited += 400;
      try {
        const st = fs.statSync(tmp);
        if (st === undefined || st === null) return;
        const size = st.size;
        if (size > 0 && size === lastSize) {
          stable++;
        } else {
          stable = 0;
        }
        lastSize = size;
        if (stable >= 2) {
          clearInterval(timer);
          this.copyToUri(tmp, uri);
        }
      } catch (err) {
        // file not created yet
      }
      if (waited > 120000) {
        clearInterval(timer);
      }
    }, 400);
  }

  private copyToUri(tmp: string, uri: string): void {
    try {
      const src = fs.openSync(tmp, fs.OpenMode.READ_ONLY);
      const dst = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(src.fd, dst.fd);
      fs.closeSync(src);
      fs.closeSync(dst);
      fs.unlinkSync(tmp);
      console.info('[LANLU-SHELL] export saved');
    } catch (err) {
      console.error('[LANLU-SHELL] export copy failed: ' + JSON.stringify(err));
    }
  }


  // Folder downloads: the engine writes into a sandbox staging dir we hand it;
  // once the files stop changing we copy them into the folder the user picked.
  private async handleFolderDialog(): Promise<void> {
    try {
      const uris = await this.withPickerTimeout(
        new picker.DocumentViewPicker(this.host!).select({ selectMode: picker.DocumentSelectMode.FOLDER }),
        120000, 'folder picker');
      if (uris === undefined || uris.length === 0) {
        this.finishDialog('');
        return;
      }
      const stage = this.host!.cacheDir + '/dl-' + Date.now();
      fs.mkdirSync(stage);
      this.finishDialog(stage);
      this.watchFolder(stage, uris[0]);
    } catch (err) {
      console.error('[LANLU-SHELL] folder dialog failed: ' + JSON.stringify(err));
      this.finishDialog('');
    }
  }

  private watchFolder(stage: string, uri: string): void {
    let lastSig = '';
    let idle = 0;
    let waited = 0;
    const timer = setInterval(() => {
      waited += 500;
      try {
        const names = fs.listFileSync(stage);
        let sig = String(names.length) + ':';
        for (let i = 0; i < names.length; i++) {
          const st = fs.statSync(stage + '/' + names[i]);
          sig += names[i] + '=' + st.size + ';';
        }
        if (names.length > 0 && sig === lastSig) {
          idle++;
        } else {
          idle = 0;
        }
        lastSig = sig;
        if (idle >= 6) {
          clearInterval(timer);
          this.copyFolderToUri(stage, uri);
        }
      } catch (err) {
        // staging dir not created yet or file gone
      }
      if (waited > 600000) {
        clearInterval(timer);
      }
    }, 500);
  }

  private copyFolderToUri(stage: string, uri: string): void {
    try {
      const names = fs.listFileSync(stage);
      for (let i = 0; i < names.length; i++) {
        const src = fs.openSync(stage + '/' + names[i], fs.OpenMode.READ_ONLY);
        // Content-folder uris accept a child name; if the provider rejects it we
        // keep the sandbox copy (the download already succeeded, just not moved).
        const dst = fs.openSync(uri + '/' + names[i], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.copyFileSync(src.fd, dst.fd);
        fs.closeSync(src);
        fs.closeSync(dst);
      }
      console.info('[LANLU-SHELL] folder download moved: ' + String(names.length) + ' file(s)');
    } catch (err) {
      console.error('[LANLU-SHELL] folder copy failed (files kept in sandbox): ' + JSON.stringify(err));
    }
  }

  // ---- 文件桥（引擎侧写请求文件，这里轮询后用系统 picker 完成）----
  // M6 第 3 步：bridgeDialogId 已删除

  private finishDialog(payload: string): void {
    // LWP 请求的对话框：结果经协议回引擎（不再写 filedlg_result.txt）
    if (this.lwpDialogSerial !== 0) {
      const serial = this.lwpDialogSerial;
      this.lwpDialogSerial = 0;
      const ok = payload !== '';
      const paths = ok ? payload.split('\n').join(';') : '';
      try { shell.lwpDialogResult(serial, paths); } catch (e) {}
      try { shell.lwpDialogClear(); } catch (e) {}
      this.dialogBusy = false;
      return;
    }
    // 没有文件桥了：LWP 请求已在上面返回；其余都交给原生回调。
    shell.completeFileDialog(payload);
  }

  // M6 第 3 步：writeBridgeFile / readBridgeFile 已删除（文件桥退役）。

  /** 把协议里的光标形状编号映射成系统 PointerStyle 并应用。 */
  private applyCursorShape(shape: number): void {
    let style: pointer.PointerStyle = pointer.PointerStyle.DEFAULT;
    // PointerStyle 的实际成员名以 SDK 为准（没有 LOADING/EAST_WEST 这类名字）
    if (shape === 1) { style = pointer.PointerStyle.TEXT_CURSOR; }
    else if (shape === 2) { style = pointer.PointerStyle.HAND_POINTING; }
    else if (shape === 3) { style = pointer.PointerStyle.DEFAULT; }
    else if (shape === 4) { style = pointer.PointerStyle.CROSS; }
    else if (shape === 5) { style = pointer.PointerStyle.MOVE; }
    else if (shape === 6) { style = pointer.PointerStyle.CURSOR_FORBID; }
    else if (shape === 7) { style = pointer.PointerStyle.RESIZE_LEFT_RIGHT; }
    else if (shape === 8) { style = pointer.PointerStyle.RESIZE_UP_DOWN; }
    else if (shape === 9) { style = pointer.PointerStyle.NORTH_WEST_SOUTH_EAST; }
    else if (shape === 10) { style = pointer.PointerStyle.NORTH_EAST_SOUTH_WEST; }
    try {
      if (this.winId < 0) { return; }
      pointer.setPointerStyle(this.winId, style).then(() => {
      }).catch((e: Error) => {
        console.warn('[LANLU-SHELL] setPointerStyle 失败: ' + JSON.stringify(e));
      });
      console.info('[LANLU-SHELL] cursor shape ' + shape);
    } catch (e) {
      console.warn('[LANLU-SHELL] setPointerStyle 异常');
    }
  }

  private lastDensity: number = 0;
  private originTick: number = 0;

  /** 用 XComponent 自己的屏幕坐标做"内容区原点"。
   *  为什么不用 windowRect：它是启动时的快照，窗口被拖动/改尺寸后会过期，
   *  于是鼠标命中和输入法候选框都会整体偏移（真机实测偏 (144,121) px）。
   *  getRectangleById 的 screenOffset 是 ArkUI 当前的权威屏幕坐标（vp）。 */
  private refreshSurfaceOrigin(): void {
    let d: number = this.lastDensity;
    if (!(d > 0)) {
      d = 1.0;
    }
    try {
      const info = this.getUIContext().getComponentUtils().getRectangleById('LGPU_Main');
      if (info !== undefined && info.screenOffset !== undefined) {
        // 实测：ComponentInfo.screenOffset 与 windowRect 同单位（**物理 px**），
        // 不能再乘密度（乘了会让原点整体放大 1.9 倍，点击与候选框全部偏移）。
        shell.seedOrigin(info.screenOffset.x, info.screenOffset.y);
        return;
      }
    } catch (e) {}
    // 回退：组件查不到（id 未进树等）时用窗口矩形，至少跟随窗口移动
    try {
      window.getLastWindow(getContext(this)).then((w: window.Window) => {
        const r = w.getWindowProperties().windowRect;
        shell.seedOrigin(r.left, r.top);
      }).catch(() => {});
    } catch (e2) {}
  }

  /** 交互式缩放：输入过滤器线程算出的待应用尺寸（与泵无关，空闲快路径也要处理）。 */
  private applyPendingResize(): void {
    try {
      const rz: number[] = shell.lwpTakeResize();
      if (rz !== undefined && rz.length === 2 && this.win !== undefined) {
        this.win.resize(rz[0], rz[1]).then(() => {
        }).catch((e: Error) => {
          console.warn('[LANLU-SHELL] resize 失败: ' + JSON.stringify(e));
        });
      }
    } catch (eRz) {}
  }

  /** 窗口当前所在显示器的 densityPixels；失败时退回默认显示器，再退回 1.0。 */
  private windowDensity(): number {
    try {
      if (this.win !== undefined) {
        const did: number = this.win.getWindowProperties().displayId ?? -1;
        if (did >= 0) {
          return display.getDisplayByIdSync(did).densityPixels;
        }
      }
    } catch (eD) {}
    try {
      return display.getDefaultDisplaySync().densityPixels;
    } catch (eDd) {
      console.warn('[LANLU-SHELL] 取 densityPixels 失败，按 1.0 处理');
    }
    return 1.0;
  }

  /** 缩放变化（拖到另一块屏 / 改系统缩放）只记录日志、不下发：引擎按 ADR 不做运行时
   *  动态缩放（DesktopApp 的 window.scale 是启动期常量），中途改 scale 会让指针换算、
   *  布局、绘制三处缩放不一致。真正支持前保持启动值。 */
  private refreshDensity(winId: number): void {
    const d: number = this.windowDensity();
    if (d > 0 && Math.abs(d - this.lastDensity) > 0.001) {
      console.warn('[LANLU-SHELL] density changed ' + this.lastDensity + ' -> ' + d +
        ' on win ' + winId + '（运行时缩放未支持，保持启动值）');
      this.lastDensity = d;
    }
  }

  /** 启动 vsync 回调：每帧检查引擎有没有 frame.request，有就回 frame.done。 */
  private startVsync(): void {
    if (this.vsyncObj !== undefined) return;
    try {
      this.vsyncObj = displaySync.create();
      const range: ExpectedFrameRateRange = { expected: 60, min: 30, max: 120 };
      this.vsyncObj.setExpectedFrameRateRange(range);
      let vsyncTicks = 0;
      let vsyncSent = 0;
      this.vsyncObj.on('frame', () => {
        try {
          vsyncTicks++;
          const serial: number = shell.lwpTakeFrameRequest();
          if (serial !== 0) {
            vsyncSent++;
            shell.lwpFrameDone(serial);
          }
          if (vsyncTicks % 120 === 0) {
            console.info('[LANLU-SHELL] vsync ticks=' + vsyncTicks + ' frameDone=' + vsyncSent);
          }
        } catch (eF) {}
      });
      this.vsyncObj.start();
      console.info('[LANLU-SHELL] vsync started');
    } catch (e) {
      console.error('[LANLU-SHELL] vsync start failed: ' + JSON.stringify(e));
      this.vsyncObj = undefined;
    }
  }

  private startLwpWindowPump(): void {
    if (this.lwpPumpTimer !== -1) return;
    this.startVsync();
    try {
      this.probeShellResize = AppStorage.get<boolean>('lanluProbeShellResize') === true;
    } catch (eP) {}
    this.lwpPumpTimer = setInterval(() => {
      let pumped: number = 0;
      try { pumped = shell.lwpWindowPump(); } catch (e) {}
      // 原点自愈：窗口被拖动/换屏后 windowRect 会过期，每秒用组件实际屏幕坐标校正一次
      if (++this.originTick % 60 === 0) {
        this.refreshSurfaceOrigin();
      }
      // 空闲快路径（评审 P2）：本拍没有任何引擎请求时，下面十几次 take* NAPI 调用都只会
      // 返回"无"。只保留不经泵的那一项（交互式缩放由输入过滤器线程写入），其余跳过，
      // 主线程每 16ms 的固定开销从 ~20 次 NAPI 降到 2 次。
      if (pumped === 0 && !this.probeShellResize) {
        this.applyPendingResize();
        return;
      }
      // 剪贴板（lw_clipboard.set/get，M6 第 2 步：文件桥换成协议）
      try {
        const cs: string = shell.lwpTakeClipboardSet();
        if (cs !== '') {
          const d = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, cs);
          pasteboard.getSystemPasteboard().setData(d)
            .then(() => { console.info('[LANLU-SHELL] clip set ok len=' + cs.length); })
            .catch((e: Error) => { console.error('[LANLU-SHELL] clip set fail ' + e.message); });
        }
      } catch (eCs) {}
      try {
        const cg: number = shell.lwpTakeClipboardGet();
        if (cg !== 0) {
          pasteboard.getSystemPasteboard().getData().then((d: pasteboard.PasteData) => {
            let text = '';
            try { text = d.getPrimaryText() ?? ''; } catch (eT) {}
            try { shell.lwpClipboardText(cg, 'text/plain', text); } catch (eR) {}
          }).catch(() => {
            try { shell.lwpClipboardText(cg, 'text/plain', ''); } catch (eR2) {}
          });
        }
      } catch (eCg) {}
      // 文本输入开关：原生输入法桥自己处理（pump 里 lw_text_input.enable/disable ->
      // lanlu_ime_enable/disable），这里只把 want 状态清掉，避免旧队列残留被误解。
      try { shell.lwpTakeImeWant(); } catch (eImeWant) {}
      // 运行期标题 / 尺寸约束（引擎 window.set_title / set_min_max）
      try {
        const t: string = shell.lwpTakeWindowTitle();
        if (t !== undefined && t.length > 0 && this.win !== undefined) {
          this.win.setWindowTitle(t).then(() => {
            console.info('[LANLU-SHELL] window title -> ' + t);
          }).catch((e: Error) => {
            console.warn('[LANLU-SHELL] setWindowTitle 失败: ' + JSON.stringify(e));
          });
        }
        const lm: number[] = shell.lwpTakeWindowLimits();
        if (lm !== undefined && lm.length === 4 && this.win !== undefined) {
          const lim: window.WindowLimits = {
            minWidth: lm[0] > 0 ? lm[0] : undefined,
            minHeight: lm[1] > 0 ? lm[1] : undefined,
            maxWidth: lm[2] > 0 ? lm[2] : undefined,
            maxHeight: lm[3] > 0 ? lm[3] : undefined,
          };
          this.win.setWindowLimits(lim).then(() => {
            console.info('[LANLU-SHELL] window limits applied');
          }).catch((e: Error) => {
            console.warn('[LANLU-SHELL] setWindowLimits 失败: ' + JSON.stringify(e));
          });
        }
      } catch (eTitle) {}
      // 帧统计（每 ~5s 一次）：证明壳确实在消费 surface.attach 的 serial
      if (this.frameLogTick++ % 300 === 0) {
        try {
          const st: number[] = shell.lwpAttachStats();
          if (st !== undefined && st.length === 3) {
            console.info('[LANLU-SHELL] frames=' + st[0] + ' lastAttachSerial=' + st[1] +
              ' backwards=' + st[2]);
          }
        } catch (eSt) {}
      }
      // 交互式缩放：引擎发 begin_resize 后，壳把指针位移换算成尺寸，这里真正改窗口
      this.applyPendingResize();
      // 光标形状：引擎请求 -> 系统光标（编号表见文档 §7.5）
      try {
        const shape: number = shell.lwpTakeCursorShape();
        if (shape >= 0) {
          this.applyCursorShape(shape);
        }
      } catch (eCur) {}
      // IME 候选框位置：原生桥（text_input.cpp）在 pump 里直接 NotifyCursorUpdate，
      // 不再经 ArkTS 的 inputMethod 控制器。这里只把待取标记清掉。
      try { shell.lwpTakeImeCursorRect(); } catch (eImeR) {}

      // 联调压测：真实改窗口几何，驱动 ArkUI 的 onSizeChange -> lw_surface.changed
      try {
        if (this.probeShellResize && this.win !== undefined) {
          this.shellResizeTick = (this.shellResizeTick + 1) % 60;   // 60 帧 ≈ 1s
          if (this.shellResizeTick === 0) {
            const w: number = 1200 + (Math.floor(Date.now() / 1000) % 5) * 120;
            this.win.resize(w, Math.floor(w * 1394 / 2090)).catch(() => {});
          }
        }
      } catch (eRs) {}
      // 引擎经协议请求的对话框（计划 §8）：引擎 ready 后由壳弹出系统选择器
      try {
        const kind: number = shell.lwpDialogRequest();
        if (kind !== 0 && !this.dialogBusy && this.lwpDialogSerial === 0) {
          this.lwpDialogSerial = shell.lwpDialogSerial();
          this.dialogBusy = true;
          const run = async (): Promise<void> => {
            let payload = '';
            try {
              if (kind === 2) {
                await this.handleSaveDialog();
              } else {
                await this.pickOpenFile();
              }
            } catch (err) {
              console.error('[LANLU-SHELL] lwp dialog failed: ' + JSON.stringify(err));
              payload = '';
            } finally {
              // handleSaveDialog/pickOpenFile 内部会调 finishDialog('')，走这里的 LWP 回执；
              // 若它们没调（异常路径），这里兜底发一条取消
              if (this.lwpDialogSerial !== 0) {
                try { shell.lwpDialogResult(this.lwpDialogSerial, ''); } catch (e2) {}
                try { shell.lwpDialogClear(); } catch (e3) {}
                this.lwpDialogSerial = 0;
                this.dialogBusy = false;
              }
            }
          };
          run();
        }
      } catch (eLwpD) {}
    }, 16);
  }

  // M6 第 3 步：filedlg_req.txt 轮询已删除（对话框只走 lw_dialog.* 与原生回调）。

  private async handleFileDialog(): Promise<void> {
    if (this.dialogBusy) return;
    const kind: number = shell.takeFileDialogRequest();
    if (kind === 0) return;
    this.dialogBusy = true;
    try {
      if (kind === 2) {
        await this.handleSaveDialog();
        return;
      }
      if (kind === 3) {
        await this.handleFolderDialog();
        return;
      }
      if (kind !== 1) {
        this.finishDialog('');
        return;
      }
      const docPicker = new picker.DocumentViewPicker(this.host!);
      const uris = await this.withPickerTimeout(docPicker.select({ maxSelectNumber: 1 }), 120000, 'open picker');
      if (uris === undefined) {
        this.finishDialog('');
        return;
      }
      if (uris === undefined || uris.length === 0) {
        this.finishDialog('');
        return;
      }
      const paths: string[] = [];
      for (let i = 0; i < uris.length; i++) {
        const dst = this.host!.cacheDir + '/pick-' + Date.now() + '-' + i;
        const src = fs.openSync(uris[i], fs.OpenMode.READ_ONLY);
        const out = fs.openSync(dst, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.copyFileSync(src.fd, out.fd);
        fs.closeSync(src);
        fs.closeSync(out);
        paths.push(dst);
      }
      this.finishDialog(paths.join('\n'));
    } catch (err) {
      console.error('[LANLU-SHELL] file dialog failed: ' + JSON.stringify(err));
      this.finishDialog('');
    } finally {
      this.dialogBusy = false;
    }
  }


  // 剪贴板桥（系统层）：SDL 的 OHOS 剪贴板读取在本机不可用（hasText=true 但取不到内容），
  // 因此由 ArkTS 直接读系统剪贴板并落文件，引擎侧按需读取（见 lwindow 的剪贴板后端）。
  // 剪贴板读取是 user_grant 权限（ohos.permission.READ_PASTEBOARD），需要运行时申请。
  private async ensurePasteboardPermission(): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = this.host as common.UIAbilityContext;
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const res: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(ctx, ['ohos.permission.READ_PASTEBOARD']);
      const results: Array<number> = res.authResults;
      console.info('[LANLU-SHELL] pasteboard permission results=' + results.join(','));
    } catch (err) {
      console.error('[LANLU-SHELL] pasteboard permission request failed: ' + JSON.stringify(err));
    }
  }

  // M6 第 2 步：pasteboard 定时读文件（clip_in.txt）已删除。

  private watchExit(host: common.UIAbilityContext): void {
    this.host = host;
    if (this.exitTimer >= 0) return;
    this.exitTimer = setInterval(() => {
      try {
        this.handleFileDialog().catch(() => {});
        // M6 第 2 步：剪贴板已全部走协议，不再定时同步沙箱文件。
        // LWP：引擎经协议请求的窗口状态/关闭/退出（计划 §7.4）
        try {
          if (shell.lwpTakeCaptureRequest() === 1) {
            // 引擎经 lw_test.request_capture 请求抓帧：复用已有的组件快照路径
            const p: string = shell.lwpCapturePath();
            console.info('[LANLU-SHELL] lwp capture -> ' + p);
            // 走已有的 `snapOnce()`（componentSnapshot -> snapshot.rgba/meta）
            try { this.snapOnce(); } catch (eSnap) {}
          }
        } catch (eCap) {}
        try {
          // 平台三键配置（引擎经 lw_window.set_title_buttons 下发）
          try {
            const cfg: number[] = shell.lwpTakeTitleButtons();
            if (cfg.length === 6) {
              this.applyTitleButtonsCfg(cfg);
            }
          } catch (eTb2) {}
          // 矩形变化（事件之外的兜底：最大化/还原后 rect 可能变化）
          try { this.reportTitleButtonRectIfChanged('poll'); } catch (eRb) {}
          const st: number = shell.lwpTakeWindowState();
          if (st !== 0 && this.win !== undefined) {
            try {
              // 注意：本 SDK 的 window.Window 没有 setWindowLayoutMode/WindowLayoutMode，
              // 全屏只能走 setWindowSystemBarEnable + 尺寸，这里先只做最大化/最小化/还原。
              // 互斥分派：此前"先按 st 分派、再无条件 minimize"的写法会让每次
              // maximize/restore 最终都被最小化（2026-11-11 修）。
              if (st === 2) {
                this.win.maximize();
              } else if (st === 1) {
                this.win.restore();
              } else if (st === 8) {
                this.win.minimize();
              } else if (st === 4) {
                this.win.maximize();   // 全屏：OHOS 无 setWindowLayoutMode，最大化近似
              }
            } catch (eSt) {}
          }
        } catch (eL) {}
        try {
          if (shell.lwpTakeCloseRequest() === 1 && this.win !== undefined) {
            this.win.destroyWindow().catch(() => {});
          }
        } catch (eC) {}
        try {
          const code: number = shell.lwpTakeExitCode();
          if (code >= 0 && this.host !== undefined) {
            console.info('[LANLU-SHELL] lwp exit ' + code + ' -> terminateSelf');
            this.host.terminateSelf();
          }
        } catch (eE) {}
        if (shell.takeMinimizeRequest() && this.win !== undefined) {
          // The title bar asked for minimize; only ArkTS can talk to the window.
          this.win.minimize().catch((err: Error) => {
            console.error('[LANLU-SHELL] minimize fail: ' + err.message);
          });
        }
        if (shell.appExited() && this.host !== undefined) {
          clearInterval(this.exitTimer);
          this.exitTimer = -1;
          console.info('[LANLU-SHELL] engine exited -> terminateSelf');
          this.host.terminateSelf();
        }
      } catch (err) {
        // engine not loaded yet
      }
    }, 400);
  }


  aboutToAppear(): void {
    try {
      this.lgpuTest = shell.lgpuWanted() === 1;
      try { this.lgpuMain = shell.lgpuMainWanted() === 1; } catch (eLm) {}
      try { this.startLwpWindowPump(); } catch (eLwpP) {}
      try {
        if (shell.inputProbeWanted() === 1) {
          let step: number = 0;
          this.inputProbeTimer = setInterval(() => {
            try {
              step = (step + 1) % 4;
              const x = step < 2 ? 300 : 900;
              const y = 200 + step * 40;
              // action: 1=down 2=move 3=up（与 L 层事件桥口径一致）
              shell.pushInput(2, x, y, 0);
              if (step === 1) { shell.pushInput(1, x, y, 0); }
              if (step === 3) { shell.pushInput(3, x, y, 0); }
            } catch (eT) {}
          }, 700);
        }
      } catch (eP) {}
    } catch (e0) {}
    // 联调：页面就绪后直接抓一次帧（setTimeout 在本环境不触发，见 R56 观测）
    try {
      console.info('[LANLU-SHELL] snap direct');
      this.snapOnce();
    } catch (eAp) {
      console.info('[LANLU-SHELL] snap direct fail ' + (eAp as Error).message);
    }
    const host = getContext(this) as common.UIAbilityContext;
    this.watchExit(host);
    window.getLastWindow(host)
      .then((w: window.Window) => {
        this.win = w;
        // 去掉系统标题栏（对齐 mihong 的做法：setWindowDecorVisible(false)，不是全屏）。
        // 应用自绘标题栏接管窗口控制；系统装饰一旦存在，窗口矩形会含装饰高度，
        // 窗口级鼠标过滤器换算出的局部坐标也会整体偏移。
        try {
          w.setWindowDecorVisible(false);
          // 自绘顶栏 56vp：系统三键（经 set_title_buttons 打开）的 y 轴跟这个高度走
          try { w.setWindowDecorHeight(56); } catch (eDH) {}
          console.info('[LANLU-SHELL] system window decor hidden');
        } catch (e2) {
          console.error('[LANLU-SHELL] decor hide fail: ' + (e2 as Error).message);
        }
        // 平台三键（docs/lwindow-title-buttons-plan.md）：decor=false 只隐藏标题栏，
        // 三键仍由系统绘制在窗口右上角。矩形以 windowTitleButtonRectChange 事件为准
        // （本机 getTitleButtonRect 返回 0，事件给 140x37vp）；vp→px 后上报引擎做避让。
        try {
          w.on('windowTitleButtonRectChange', (r: window.TitleButtonRect) => {
            this.lastTitleBtnRect = r;
            this.reportTitleButtonRectIfChanged('evt');
          });
          console.info('[LANLU-SHELL] title btn rect listener ok');
        } catch (eTb) {
          console.info('[LANLU-SHELL] title btn rect listener failed: ' + (eTb as Error).message);
        }
        // 系统关闭钮：windowWillClose 拦截回调里把事件转给引擎（等价 xdg_toplevel.close），
        // resolve(false) = 放行系统关闭；引擎按 lw_window.close_request 走既有退出流程。
        try {
          w.on('windowWillClose', () => {
            try {
              shell.lwpSendCloseRequest();
            } catch (eC) {}
            return Promise.resolve(false);
          });
          console.info('[LANLU-SHELL] windowWillClose listener ok');
        } catch (eWc) {
          console.info('[LANLU-SHELL] windowWillClose listener failed: ' + (eWc as Error).message);
        }
        const props = w.getWindowProperties();
        const rect = props.windowRect;
        // Seed the native mouse filter with the real window id and rect
        // origin (rect includes chrome; native self-calibrates continuously).
        const rc: number = shell.startFilter(props.id, rect.left, rect.top);
        console.info('[LANLU-SHELL] startFilter win=' + props.id + ' rect=(' + rect.left + ',' + rect.top + ',' + rect.width + ',' + rect.height + ') rc=' + rc);
        this.winId = props.id;
        // 窗口移动/缩放/最大化：重新种入鼠标过滤器原点（过滤器给的是屏幕坐标），
        // 并把新尺寸作为 configure 下发；缩放比例（跨屏/改系统缩放）一并刷新。
        // 之前原点只在启动时种一次 —— 窗口一拖动，所有点击整体偏移（评审 M1/W4）。
        try {
          w.on('windowRectChange', (opt: window.RectChangeOptions) => {
            try {
              const nr = opt.rect;
              // 先用组件真实屏幕坐标（权威），窗口矩形只作为 configure 的尺寸来源
              this.refreshSurfaceOrigin();
              shell.lwpWindowConfigure(nr.width, nr.height, 1);
              this.refreshDensity(props.id);
            } catch (eRc) {}
          });
          console.info('[LANLU-SHELL] windowRectChange listener ok');
        } catch (eRcL) {
          console.info('[LANLU-SHELL] windowRectChange listener failed: ' + (eRcL as Error).message);
        }
        // LWP（计划 §7）：把窗口创建与初始尺寸告诉引擎；LANLU_LWP 未开时这些调用是空操作。
        try {
          // 系统缩放（如 PC 模式 200%）必须如实上报，否则引擎按 1x 渲染，
          // 内容只铺满左上 1/scale² 区域（第 116 轮真机症状：右侧纯黑）
          // 窗口所在显示器的密度（不是默认显示器：外接屏/扩展屏缩放不同）
          let sysDensity = this.windowDensity();
          this.lastDensity = sysDensity;
          console.info('[LANLU-SHELL] window created density=' + sysDensity);
          shell.lwpWindowCreated(props.id, sysDensity, false);
          shell.lwpWindowConfigure(rect.width, rect.height, 1);
          shell.lwpAppResumed();
          console.info('[LANLU-SHELL] lwp window created id=' + props.id + ' ' + rect.width + 'x' + rect.height);
        } catch (eLwp) {}
        // 窗口几何取证：检查系统装饰是否真的没了（有标题栏时 top 避让区 > 0）。
        try {
          const sysArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          const cutArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
          const navArea = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          const line: string = 'rect=' + rect.left + ',' + rect.top + ',' + rect.width + ',' + rect.height +
            ' sysTop=' + sysArea.topRect.height + ' sysBottom=' + sysArea.bottomRect.height +
            ' cutTop=' + cutArea.topRect.height + ' navBottom=' + navArea.bottomRect.height +
            '\n';
          const f = fs.openSync('/data/storage/el2/base/files/window_info.txt',
            fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
          fs.writeSync(f.fd, line);
          fs.closeSync(f);
        } catch (eW0) {}
        // 关窗链路探针（LANLU_PROBE_CLOSE=1）：2 秒后模拟系统关闭钮，
        // 验证 windowWillClose -> lwpSendCloseRequest -> 引擎 close_request -> 退出。
        try {
          if (AppStorage.get<boolean>('lanluProbeClose') === true) {
            let n: number = 0;
            const t = setInterval(() => {
              n = n + 1;
              if (n >= 4) {
                clearInterval(t);
                try {
                  const rc: number = shell.lwpSendCloseRequest();
                  console.info('[LANLU-SHELL] probe close_request sent rc=' + rc);
                } catch (eC) {}
              }
            }, 500);
          }
        } catch (ePc) {}
        // 输入法挂载改由引擎的 lw_text_input.enable 驱动（焦点进入输入框时），
        // 这里只把窗口 id 与"是否弹软键盘"告诉原生桥。
        try {
          const t = deviceInfo.deviceType;
          // 第三个参数是 UI 密度：native 用它把逻辑 vp 的光标矩形换成物理 px
          const dens: number = this.lastDensity > 0 ? this.lastDensity : this.windowDensity();
          shell.imeSetWindow(props.id, t !== '2in1' && t !== 'tablet', dens);
        } catch (eIw) {}
      })
      .catch((e: Error) => {
        console.error('[LANLU-SHELL] getLastWindow fail: ' + e.message);
      });
  }

  // ── 平台三键（docs/lwindow-title-buttons-plan.md）────────────────────────
  // 引擎经 lw_window.set_title_buttons 下发的配置：[visible, side, close_margin,
  // spacing, button_size, color_mode]。OHOS 只支持右上角区域内调 margin/spacing/size
  // （6..22 / 8..24 / 20..40 vp），超范围 clamp；801（非自由窗口设备）时跳过。
  private applyTitleButtonsCfg(cfg: number[]): void {
    if (this.win === undefined) {
      return;
    }
    const visible: number = cfg[0];
    // 三键的垂直位置由"装饰条高度"决定（系统默认约 40vp，而我们自绘顶栏 56vp）；
    // 不对齐时系统三键浮在顶栏上方。setWindowDecorHeight 范围 [37,112] vp，56 = TITLEBAR_HEIGHT。
    // 单独 try：这一步失败（部分设备 801）不能把下面的"显示三键"一起跳过。
    try {
      this.win.setWindowDecorHeight(56);
    } catch (eDH) {
      console.info('[LANLU-SHELL] setWindowDecorHeight failed: ' + (eDH as Error).message);
    }
    try {
      // 装饰条已隐藏：系统三键不渲染（渲染出来也无处安放），统一交给引擎自绘
      this.win.setWindowTitleButtonVisible(false, false, false);
    } catch (eVis) {
      console.info('[LANLU-SHELL] title button visibility failed: ' + (eVis as Error).message);
    }
    const clamp = (v: number, lo: number, hi: number): number => {
      return v < lo ? lo : (v > hi ? hi : v);
    };
    try {
      let mode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
      if (cfg[5] === 1) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      } else if (cfg[5] === 2) {
        mode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      }
      this.win.setDecorButtonStyle({
        closeButtonRightMargin: clamp(cfg[2], 6, 22),
        spacingBetweenButtons: clamp(cfg[3], 8, 24),
        buttonBackgroundSize: clamp(cfg[4], 20, 40),
        colorMode: mode
      });
      console.info('[LANLU-SHELL] title buttons cfg applied visible=0x' + visible.toString(16)
        + ' mode=' + cfg[5]);
    } catch (eStyle) {
      console.info('[LANLU-SHELL] decor button style failed: ' + (eStyle as Error).message);
    }
    this.reportTitleButtonRectIfChanged('cfg');
  }

  // 三键矩形上报（px）：事件给的 vp → px；只在变化时发，避免每 400ms 刷屏。
  // 本机 getTitleButtonRect 返回 0，因此优先用事件缓存（lastTitleBtnRect）。
  private reportTitleButtonRectIfChanged(src: string): void {
    if (this.win === undefined) {
      return;
    }
    let rect: window.TitleButtonRect | undefined = undefined;
    try {
      const r: window.TitleButtonRect = this.win.getTitleButtonRect();
      if (r.width > 0 && r.height > 0) {
        rect = r;
      }
    } catch (eG) {}
    if (rect === undefined) {
      rect = this.lastTitleBtnRect;
    }
    if (rect === undefined) {
      return;
    }
    const ui = this.getUIContext();
    const rightPx: number = rect.right > 0 ? Math.round(ui.vp2px(rect.right)) : 0;
    const topPx: number = Math.round(ui.vp2px(rect.top));
    const wPx: number = Math.round(ui.vp2px(rect.width));
    const hPx: number = Math.round(ui.vp2px(rect.height));
    // 本应用始终 setWindowDecorVisible(false)（自绘 56vp 顶栏）：系统装饰条不渲染，
    // 平台三键也就画不出来。此时必须报 visible=0，让引擎自绘三键 —— 否则引擎以为
    // "平台会画"，右侧留白 140vp 却谁都画不出按钮（真机表现：右上角空白、无法关窗）。
    const vis: number = 0;
    if (rightPx === this.titleBtnReportedPx[0] && topPx === this.titleBtnReportedPx[1]
      && wPx === this.titleBtnReportedPx[2] && hPx === this.titleBtnReportedPx[3]
      && vis === this.titleBtnReportedPx[4]) {
      return;
    }
    this.titleBtnReportedPx = [rightPx, topPx, wPx, hPx, vis];
    try {
      shell.lwpTitleButtonRect(rightPx, topPx, wPx, hPx, vis);
      console.info('[LANLU-SHELL] title btn rect[' + src + '] vp=' + JSON.stringify(rect)
        + ' px=' + rightPx + ',' + topPx + ' ' + wPx + 'x' + hPx);
    } catch (eR) {
      console.info('[LANLU-SHELL] title btn rect send failed: ' + (eR as Error).message);
    }
  }


  // 联调日志：写入 filesDir/poll_log.txt（hilog 会被限流，文件不受影响）。
  private pollLog(msg: string): void {
    try {
      // 与 clip_* 同一个目录（应用级 files），shell 可直接查看。
      // 注意：不要在定时器回调里用 getContext(this)，可能抛异常被静默吞掉。
      const p: string = '/data/storage/el2/base/files/poll_log.txt';
      const f = fs.openSync(p, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(f.fd, msg + '\n');
      fs.closeSync(f);
    } catch (e) {}
  }

  // 抓帧桥：引擎写 snapshot_req.txt 请求当前页面截图，这里用 componentSnapshot 抓帧后
  // 写成原始 RGBA（snapshot.rgba）+ 尺寸（snapshot.meta），引擎侧做 CPU 高斯模糊。
  // 联调：用 callback 版抓帧并对每种失败打印完整错误对象
  private snapTry(id: string, tag: string): void {
    try {
      this.getUIContext().getComponentSnapshot().get(id, (err: BusinessError, pm: image.PixelMap) => {
        if (err) {
          this.snapLog(tag + ' cb err ' + JSON.stringify(err) + ' code=' + err.code);
          return;
        }
        this.snapLog(tag + ' cb ok');
        try { pm.release(); } catch (e0) {}
      });
    } catch (e1) {
      this.snapLog(tag + ' throw ' + JSON.stringify(e1));
    }
  }

  // 联调：直接抓一次帧（不经过引擎请求文件）
  private snapOnce(): void {
    this.snapLog('once: start');
    this.snapTry('snap_probe_vis', 'vis');
    this.snapTry('snap_probe', 'plain');
    this.snapTry('lanlu_root', 'root');
    try {
      this.getUIContext().getComponentSnapshot().get('snap_probe').then((pm0: image.PixelMap) => {
        this.snapLog('probe ok');
        try { pm0.release(); } catch (eP0) {}
      }).catch((eP: Error) => { this.snapLog('probe fail ' + JSON.stringify(eP)); });
      this.getUIContext().getComponentSnapshot().get('lanlu_root').then((pm: image.PixelMap) => {
        this.snapLog('once: get ok');
        pm.getImageInfo().then((info: image.ImageInfo) => {
          const w: number = info.size.width;
          const h: number = info.size.height;
          this.snapLog('once: info ' + w + 'x' + h);
          const buf = new ArrayBuffer(w * h * 4);
          pm.readPixelsToBuffer(buf).then(() => {
            this.snapLog('once: pixels ' + buf.byteLength);
            try {
              this.writeWhole('/data/storage/el2/base/files/snapshot.meta', w + ' ' + h);
              const f = fs.openSync('/data/storage/el2/base/files/snapshot.rgba',
                fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
              fs.writeSync(f.fd, buf);
              fs.closeSync(f);
              this.snapLog('once: written');
            } catch (eW) { this.snapLog('once: write fail ' + (eW as Error).message); }
            try { pm.release(); } catch (eR) {}
          }).catch((eR2: Error) => { this.snapLog('once: pixels fail ' + eR2.message); });
        }).catch((eI: Error) => { this.snapLog('once: info fail ' + eI.message); });
      }).catch((eG: Error) => { this.snapLog('once: get fail ' + JSON.stringify(eG)); });
    } catch (eS) { this.snapLog('once: throw ' + (eS as Error).message); }
  }

  // 协议可用时文件桥整体停用（计划 §11「已短路」的运行时判据）
  private lwpActive(): boolean {
    try { return shell.lwpEnabled() === 1; } catch (e) { return false; }
  }

  // M6 第 4 步：snapshot_req.txt 轮询已删除（抓帧只走 lw_test.request_capture）。

  build() {
    Row() {
      Column() {
        // P5：SDL 的 XComponent 已移除（L 层窗口 + lgpu 渲染取代它）
        // 抓帧探针：普通组件（不含 XComponent SURFACE），用于验证 componentSnapshot 可用性
        Text('snap-probe').id('snap_probe').width(40).height(20).opacity(0)
        Text('V').id('snap_probe_vis').width(40).height(20).backgroundColor(Color.Red)
      }
      .width('100%')
      if (this.lgpuMain) {
        XComponent({ id: 'LGPU_Main', type: XComponentType.SURFACE, controller: this.lgpuMainCtl })
          // 构造参数里的 id 不进 UI 树（只有 .id() 属性才进），而 getRectangleById 按属性 id 查；
          // 没有它就拿不到组件真实屏幕坐标，鼠标命中与输入法候选框都会偏移。
          .id('LGPU_Main')
          .width('100%')
          .height('100%')
          // 父容器是 Column（纵向排列），不加绝对定位会被排到 SDL XComponent 下方而不可见
          .position({ x: 0, y: 0 })
          .zIndex(9)
          // 滚轮/触摸板 -> lw_input.pointer_axis（窗口鼠标过滤器收不到 AXIS，只能走 ArkUI 事件）
          .onAxisEvent((event: AxisEvent) => {
            try {
              const vy: number = event.getVerticalAxisValue();
              const vx: number = event.getHorizontalAxisValue();
              // ÷45：ArkUI 给的是像素量，协议用「逻辑刻度」（与文件桥时期同一换算）
              if (Math.abs(vy) > 0) { shell.lwpSendPointerAxis(vy / 45.0, 0); }
              if (Math.abs(vx) > 0) { shell.lwpSendPointerAxis(vx / 45.0, 1); }
            } catch (eAx) {}
          })
          // 输入法不消费的可打印键（数字、部分符号）兜底：OHOS 的键先给输入法，输入法没吃的
          // 才落到获得焦点的组件。PC 上的华为输入法不处理数字键，而 IME 挂着时窗口键盘过滤器
          // 又停发键码（防字母重复）—— 数字两头落空，输入框里打不出来。
          // 与 horizon 同一做法：组件 onKeyEvent 收到的就是输入法放行的键，转成文本发给引擎。
          .focusable(true)
          .defaultFocus(true)
          // 键事件唯一入口（输入法消费的键不会到这里，见 text_input.cpp 的 consumeKeyEvents）。
          // 携带 unicode 文本与修饰键：输入框从文本插入，控件快捷键仍能收到键。
          .focusable(true)
          .defaultFocus(true)
          // 指针：用组件内坐标（vp）× 密度 = 物理 px，不依赖窗口原点；同一个事件里
          // displayX-x 就是组件在屏幕上的起点（vp），顺手校准给输入法候选框。
          .onMouse((e: MouseEvent) => {
            try {
              const dens: number = this.lastDensity > 0 ? this.lastDensity : 1.0;
              const ox: number = (e.displayX - e.x) * dens;
              const oy: number = (e.displayY - e.y) * dens;
              if (ox > 0 || oy > 0) {
                try { shell.calibrateOriginFromEvent(ox, oy); } catch (eC) {}
              }
              let act: number = 10;   // move
              if (e.action === MouseAction.Press) { act = 11; }
              else if (e.action === MouseAction.Release) { act = 12; }
              else if (e.action === MouseAction.Move) { act = 10; }
              let btn: number = 0;
              if (e.button === MouseButton.Right) { btn = 1; }
              else if (e.button === MouseButton.Middle) { btn = 2; }
              shell.sendPointerLocal(act, e.x * dens, e.y * dens, btn);
            } catch (eM) {}
          })
          .onAreaChange((_o: Area, _n: Area) => { this.refreshSurfaceOrigin(); })
          .onFocus(() => { try { shell.setComponentFocused(true); } catch (eF) {} })
          .onBlur(() => { try { shell.setComponentFocused(false); } catch (eB) {} })
          .onKeyEvent((event: KeyEvent) => {
            const down: boolean = event.type === KeyType.Down;
            const mods: number = LanluKeyMods.mask(event);
            const text: string = down ? LanluKeyMods.text(event, mods) : '';
            let rc: number = 0;
            try { rc = shell.sendKeyEvent(event.keyCode, down, text, mods); } catch (eK) {}
            if (rc === 1) {
              event.stopPropagation();
            }
          })
          // 尺寸变化 -> lw_surface.changed：由 LanluMainXcController.onSurfaceChanged（px）上报，
          // 不再用 onSizeChange（vp）。
          .onLoad(() => {
            try {
              const sid: string = this.lgpuMainCtl.getXComponentSurfaceId();
              // 真实像素尺寸取自窗口属性（windowRect 是 px）；getXComponentSurfaceRect 不可用/为 0。
              window.getLastWindow(getContext(this)).then((win: window.Window) => {
                try {
                  const wp: window.WindowProperties = win.getWindowProperties();
                  const r = wp.windowRect;
                  // 优先用 XComponent 自己的 surface 尺寸（px）；拿不到才退回窗口矩形
                  let sw: number = this.lgpuMainCtl.lastW;
                  let sh: number = this.lgpuMainCtl.lastH;
                  if (sw <= 0 || sh <= 0) {
                    try {
                      const sr: SurfaceRect = this.lgpuMainCtl.getXComponentSurfaceRect();
                      sw = Math.round(sr.surfaceWidth);
                      sh = Math.round(sr.surfaceHeight);
                    } catch (eSr) {}
                  }
                  if (sw <= 0 || sh <= 0) {
                    sw = r.width;
                    sh = r.height;
                  }
                  this.lgpuMainCtl.lastW = sw;
                  this.lgpuMainCtl.lastH = sh;
                  shell.setMainSurface(Number(sid), sw, sh);
                  this.lgpuMainCtl.surfaceReady = true;
                  this.refreshSurfaceOrigin();
                  // P5：引擎由壳层启动（不再经 SDL_main）
                  try { shell.startEngine(); } catch (eEn) {}
                  console.info('[LANLU-SHELL] lgpu main surfaceId=' + sid + ' ' + sw + 'x' + sh +
                    ' (windowRect ' + r.width + 'x' + r.height + ')');
                } catch (eW) {}
              }).catch((eP: Error) => {});
            } catch (eM) {}
          })
      }
      if (this.lgpuTest) {
        XComponent({ id: 'LGPU_Test', type: XComponentType.SURFACE, controller: this.lgpuCtl })
          .width(240)
          .height(160)
          .position({ x: 8, y: 8 })
          .onLoad(() => {
            try {
              const sid: string = this.lgpuCtl.getXComponentSurfaceId();
              // 先把 surfaceId 公布进进程环境（lwindow 自建窗口要用），再决定谁建 surface
              try {
                shell.stagePng();
              } catch (e0) {}
              try {
                shell.setSurfaceId(Number(sid));
              } catch (e8) {}
              let rc: number = 0;
              try {
                rc = shell.lgpuTest(Number(sid), 240, 160);
              } catch (e9) {}
              let diag: string = '';
              try {
                diag = shell.lgpuLastError();
              } catch (e6) {}
              console.info('[LANLU-SHELL] lgpu test surfaceId=' + sid + ' rc=' + rc + ' diag=' + diag);
              let trc: number = 0;
              let tdiag: string = '';
              try {
                trc = shell.lgpuTextSelftest();
                tdiag = shell.lgpuLastError();
              } catch (e7) {}
              console.info('[LANLU-SHELL] lgpu text selftest rc=' + trc + ' diag=' + tdiag);
            } catch (e5) {
              console.error('[LANLU-SHELL] lgpu test failed: ' + (e5 as Error).message);
            }
          })
      }
    }
    .id('lanlu_root')
    .height('100%')
  }
}
