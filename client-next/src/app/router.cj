package lanlu_client_next.app

// 无路由框架：状态驱动切页（参考 examples/calendar、examples/wizard）。
public enum Page {
    | Login
    | Library
    | Shelf
    | Detail(String)          // arcid
    | Tank(String)            // tankoubon_id
    | Reader(String, Int64)   // arcid, 起始页（1 基）
    | Settings
}

// 页相等比较：带参 enum 不直接支持 ==，navigate 用它做同页检测（同页不播过渡）。
public func pageEquals(a: Page, b: Page): Bool {
    match (a) {
        case Page.Login => match (b) {
            case Page.Login => true
            case _ => false
        }
        case Page.Library => match (b) {
            case Page.Library => true
            case _ => false
        }
        case Page.Shelf => match (b) {
            case Page.Shelf => true
            case _ => false
        }
        case Page.Detail(x) => match (b) {
            case Page.Detail(y) => x == y
            case _ => false
        }
        case Page.Tank(x) => match (b) {
            case Page.Tank(y) => x == y
            case _ => false
        }
        case Page.Reader(x, p) => match (b) {
            case Page.Reader(y, q) => x == y && p == q
            case _ => false
        }
        case Page.Settings => match (b) {
            case Page.Settings => true
            case _ => false
        }
    }
}
