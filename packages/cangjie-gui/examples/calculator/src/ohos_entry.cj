package cui_calculator

import cui.{DesktopApp, EventHandler, WindowSpec}

@C
public func cj_app_main(): Int64 {
    let model = CalcModel()
    let app = DesktopApp(WindowSpec("CUI 计算器", 480, 600, resizable: false, scale: 1.5, fontPath: Some("/system/fonts/HarmonyOS_Sans_SC.ttf")), theme: calculatorTheme())
    app.run {
        EventHandler(onEvent: {event => handleCalculatorEvent(model, event)}) {
            calculatorView(model)
        }
    }
    return 0
}
