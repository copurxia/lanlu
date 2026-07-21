package lanlu_client_next.app

// 无路由框架：状态驱动切页（参考 examples/calendar、examples/wizard）。
public enum Page {
    | Login
    | Library
    | Detail(String)          // arcid
    | Tank(String)            // tankoubon_id
    | Reader(String, Int64)   // arcid, 起始页（1 基）
    | Settings
}
