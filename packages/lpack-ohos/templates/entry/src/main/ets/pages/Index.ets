import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN: number = 0x0000; const TAG: string = 'CJPROBE';

@Entry
@Component
struct Index {
  private controller: XComponentController = new XComponentController();
  build() {
    Stack() {
      XComponent({
        id: 'cjxc',
        type: XComponentType.SURFACE,
        libraryname: '__SHIM__',
        controller: this.controller
      })
        .id('cjxc')
        .width('100%')
        .height('100%')
        .onLoad(() => { hilog.info(DOMAIN, TAG, 'XComponent loaded lib__SHIM__.so'); })
        .onDestroy(() => { hilog.info(DOMAIN, TAG, 'XComponent destroyed'); })
    }.width('100%').height('100%').backgroundColor(Color.Black)
  }
}
