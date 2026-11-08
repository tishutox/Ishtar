# Flutter Llama - CMake configuration for Android with llama.cpp
# Based on llama.cpp/examples/llama.android approach

cmake_minimum_required(VERSION 3.10.2)

project(flutter_llama)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 16 KB page sizes (flutter_llama 1.2.1): Android 15+ devices with 16 KB pages need every shared library's LOAD segments
# aligned to 16 KB, and Google Play requires it. NDK r28 does this by default; older NDKs (the plugin module may get
# AGP's default NDK) need the flag. It applies to llama.cpp / ggml too, which are added below.
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_MODULE_LINKER_FLAGS "${CMAKE_MODULE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_C_STANDARD 11)

# Find required packages
find_library(log-lib log)
find_library(android-lib android)

# llama.cpp configuration
# llama.cpp: the checkout next to the package (git / development), else the same pinned commit as src/core (a pub.dev
# install, where llama.cpp/ is not in the archive; sdd-flutter-llama-agent 4.3).
set(LLAMA_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../../llama.cpp")
set(FL_LLAMA_CPP_COMMIT cd959bae99ff4bed22bef2604f45241c09bbb8c8)
if(NOT EXISTS "${LLAMA_CPP_DIR}/CMakeLists.txt")
    include(FetchContent)
    FetchContent_Declare(llama_cpp GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git GIT_TAG ${FL_LLAMA_CPP_COMMIT})
    FetchContent_GetProperties(llama_cpp)
    if(NOT llama_cpp_POPULATED)
        FetchContent_Populate(llama_cpp)
    endif()
    set(LLAMA_CPP_DIR "${llama_cpp_SOURCE_DIR}")
endif()

# Configure llama.cpp build
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)

# Disable features not needed for mobile
set(GGML_USE_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_AMX OFF CACHE BOOL "" FORCE)

# GPU Acceleration for Android devices
# Vulkan for modern devices (Android 7.0+)
# OpenCL as fallback for older devices
# CPU backend with NEON as last resort

# Try to enable Vulkan (best performance on modern devices)
# Backends are runtime modules (GGML_BACKEND_DL): libggml-cpu.so is always there; libggml-vulkan.so is built against the
# API 28 libvulkan (ggml-vulkan needs Vulkan 1.1 symbols such as vkGetPhysicalDeviceFeatures2) and loaded only when the
# device has them. On Android 7 / 8 the load fails and the model runs on the CPU; nothing links to the GPU module, so the
# app itself still installs and starts on minSdk 24 (sdd-flutter-llama-agent 1.2).
option(FLUTTER_LLAMA_ANDROID_VULKAN "Build the optional Vulkan backend module" OFF)
set(GGML_BACKEND_DL ON CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS ON CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
if(FLUTTER_LLAMA_ANDROID_VULKAN)
    set(vulkan-lib "${CMAKE_SYSROOT}/usr/lib/${ANDROID_TOOLCHAIN_NAME}/28/libvulkan.so")
    if(NOT EXISTS "${vulkan-lib}")
        file(GLOB vulkan-lib "${ANDROID_NDK}/toolchains/llvm/prebuilt/*/sysroot/usr/lib/aarch64-linux-android/28/libvulkan.so")
    endif()
    set(Vulkan_LIBRARY "${vulkan-lib}" CACHE FILEPATH "" FORCE)
endif()
if(vulkan-lib)
    set(GGML_VULKAN ON CACHE BOOL "" FORCE)
    # The NDK ships the Vulkan C headers only; ggml-vulkan needs the C++ ones (vulkan.hpp). Khronos Vulkan-Headers
    # (Apache-2.0), fetched at configure time (sdd-flutter-llama-agent 1.2; found by the LienDeed Android release build).
    include(FetchContent)
    FetchContent_Declare(vulkan_headers GIT_REPOSITORY https://github.com/KhronosGroup/Vulkan-Headers.git GIT_TAG v1.4.309 GIT_SHALLOW TRUE)
    FetchContent_GetProperties(vulkan_headers)
    if(NOT vulkan_headers_POPULATED)
        FetchContent_Populate(vulkan_headers)
    endif()
    include_directories(BEFORE SYSTEM ${vulkan_headers_SOURCE_DIR}/include)

    # ggml-vulkan also does find_package(SPIRV-Headers CONFIG) and includes
    # <spirv/unified1/spirv.hpp>. The LunarG Vulkan SDK normally provides the
    # config package; fetch SPIRV-Headers and supply a minimal config instead.
    FetchContent_Declare(spirv_headers GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Headers.git GIT_TAG vulkan-sdk-1.4.309.0 GIT_SHALLOW TRUE)
    FetchContent_GetProperties(spirv_headers)
    if(NOT spirv_headers_POPULATED)
        FetchContent_Populate(spirv_headers)
    endif()
    include_directories(BEFORE SYSTEM ${spirv_headers_SOURCE_DIR}/include)
    set(_spirv_headers_config_dir "${CMAKE_BINARY_DIR}/spirv-headers-config")
    file(MAKE_DIRECTORY "${_spirv_headers_config_dir}")
    file(WRITE "${_spirv_headers_config_dir}/SPIRV-HeadersConfig.cmake"
        "set(SPIRV-Headers_INCLUDE_DIRS \"${spirv_headers_SOURCE_DIR}/include\")\n")
    set(SPIRV-Headers_DIR "${_spirv_headers_config_dir}" CACHE PATH "" FORCE)

    message(STATUS "🚀 Vulkan GPU acceleration ENABLED")
    message(STATUS "   Supported: Adreno 5xx+, Mali-G71+, Samsung Exynos 9+")
    message(STATUS "   Expected: 4-8x faster than CPU")
else()
    # Try OpenCL as fallback
    find_library(opencl-lib OpenCL)
    if(opencl-lib)
        set(GGML_OPENCL ON CACHE BOOL "" FORCE)
        message(STATUS "⚡ OpenCL GPU acceleration ENABLED (fallback)")
        message(STATUS "   Supported: Most Android devices with GPU")
        message(STATUS "   Expected: 2-5x faster than CPU")
    else()
        message(STATUS "⚡ Using optimized CPU backend with ARM NEON")
        message(STATUS "   GPU libraries not found, falling back to CPU")
    endif()
endif()

message(STATUS "   Works on: All ARM64 Android devices")

# Add llama.cpp as subdirectory (it will build its own CMakeLists.txt)
add_subdirectory(${LLAMA_CPP_DIR} build-llama)

# Create our JNI bridge library
add_library(flutter_llama_bridge SHARED
    flutter_llama_bridge.cpp
)

# Include directories
target_include_directories(flutter_llama_bridge PRIVATE
    ${LLAMA_CPP_DIR}/include
    ${LLAMA_CPP_DIR}/src
    ${LLAMA_CPP_DIR}/ggml/include
    ${LLAMA_CPP_DIR}/common
)

# Link with llama.cpp libraries
target_link_libraries(flutter_llama_bridge
    llama
    ${log-lib}
    ${android-lib}
)

# GPU backends are modules loaded at runtime (see GGML_BACKEND_DL above); the bridge links none of them.

if(opencl-lib)
    target_link_libraries(flutter_llama_bridge ${opencl-lib})
    message(STATUS "  Linked: OpenCL library")
endif()

message(STATUS "Flutter Llama Bridge configuration:")
message(STATUS "  Android ABI: ${ANDROID_ABI}")
message(STATUS "  llama.cpp Dir: ${LLAMA_CPP_DIR}")
message(STATUS "  Build Type: ${CMAKE_BUILD_TYPE}")
