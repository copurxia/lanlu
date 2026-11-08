# lanlu_client_platform

client-next 平台抽象（迁移第一步）。定义 Window/Renderer/AppRuntime/PlatformPaths/PlatformBackend 接口，
纯仓颉、不含 cui/SDL 类型。桌面后端用 CangjieGUI(SDL)，OHOS 后端将用 SDL3（HarmonyOS port）。
