cmake_minimum_required(VERSION 3.5.0)
project(__SHIM__)
add_library(__SHIM__ SHARED napi_init.cpp)
target_link_libraries(__SHIM__ PUBLIC ace_napi.z ace_ndk.z hilog_ndk.z ability_runtime EGL GLESv3 dl)
