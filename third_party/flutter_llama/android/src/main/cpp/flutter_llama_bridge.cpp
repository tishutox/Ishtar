/*
 * Flutter Llama - JNI Bridge for Android
 * 
 * This file provides JNI bindings between Kotlin and llama.cpp
 * Updated for latest llama.cpp API
 */

#include <jni.h>
#include <string>
#include <vector>
#include <mutex>
#include <android/log.h>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <dlfcn.h>
#include <unwind.h>

#define LOG_TAG "FlutterLlamaBridge"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Include llama.cpp headers
#include "llama.h"

// Global state
static llama_model* g_model = nullptr;
static llama_context* g_context = nullptr;
static const llama_vocab* g_vocab = nullptr;
static llama_sampler* g_sampler = nullptr;
static std::mutex g_mutex;
static bool g_should_stop = false;
static std::vector<std::string> g_stream_tokens;
static size_t g_stream_pos = 0;

// Native crash logger: writes the signal, faulting library and a backtrace
// to a file so a native crash (SIGSEGV/SIGABRT etc.) can be diagnosed.
static char g_crash_log_path[512] = {0};

struct BacktraceState {
    void** current;
    void** end;
};

static _Unwind_Reason_Code backtrace_callback(struct _Unwind_Context* ctx, void* arg) {
    BacktraceState* state = (BacktraceState*)arg;
    uintptr_t pc = _Unwind_GetIP(ctx);
    if (pc) {
        if (state->current == state->end) return _URC_END_OF_STACK;
        *state->current++ = (void*)pc;
    }
    return _URC_NO_REASON;
}

static void crash_signal_handler(int sig, siginfo_t* info, void* /*ctx*/) {
    FILE* f = fopen(g_crash_log_path, "a");
    if (f) {
        fprintf(f, "=== Native crash: signal %d ===\n", sig);
        if (info && info->si_addr) {
            fprintf(f, "Fault address: %p\n", info->si_addr);
        }
        fprintf(f, "Backtrace:\n");
        void* frames[64];
        BacktraceState state = { frames, frames + 64 };
        _Unwind_Backtrace(backtrace_callback, &state);
        int n = (int)(state.current - frames);
        for (int i = 0; i < n; i++) {
            Dl_info dl;
            if (dladdr(frames[i], &dl) && dl.dli_fname) {
                fprintf(f, "#%02d %s", i, dl.dli_fname);
                if (dl.dli_sname) fprintf(f, " (%s)", dl.dli_sname);
                if (dl.dli_fbase) {
                    fprintf(f, " +0x%lx",
                            (unsigned long)((char*)frames[i] - (char*)dl.dli_fbase));
                }
                fprintf(f, "\n");
            } else {
                fprintf(f, "#%02d %p\n", i, frames[i]);
            }
        }
        fflush(f);
        fclose(f);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

extern "C" {

// The registered compute devices, e.g. "CPU;Vulkan0 (Mali-G57)" (sdd-flutter-llama-agent 1.2).
JNIEXPORT jstring JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeBackendInfo(JNIEnv* env, jobject /* thiz */) {
    std::string out;
    for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
        ggml_backend_dev_t dev = ggml_backend_dev_get(i);
        if (!out.empty()) out += ";";
        out += std::string(ggml_backend_dev_name(dev)) + " (" + ggml_backend_dev_description(dev) + ")";
    }
    return env->NewStringUTF(out.c_str());
}

// Install the native crash logger so a SIGSEGV/etc. is written to [logPath].
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeInstallCrashLogger(
    JNIEnv* env, jobject /* thiz */, jstring logPath) {
    const char* path = env->GetStringUTFChars(logPath, nullptr);
    strncpy(g_crash_log_path, path, sizeof(g_crash_log_path) - 1);
    g_crash_log_path[sizeof(g_crash_log_path) - 1] = '\0';
    env->ReleaseStringUTFChars(logPath, path);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crash_signal_handler;
    sa.sa_flags = SA_SIGINFO;
    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
}

// Initialize and load model
JNIEXPORT jboolean JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeInitModel(
    JNIEnv* env,
    jobject thiz,
    jstring model_path,
    jint n_threads,
    jint n_gpu_layers,
    jint context_size,
    jint batch_size,
    jboolean use_gpu,
    jboolean verbose
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    const char* path = env->GetStringUTFChars(model_path, nullptr);
    
    LOGI("Initializing model: %s", path);
    LOGI("Threads: %d, GPU layers: %d, Context: %d", n_threads, n_gpu_layers, context_size);
    
    // Free existing model if any
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }
    
    // Backends are modules (GGML_BACKEND_DL), loaded once by name: the app's linker namespace finds them inside the APK
    // even when native libraries are not extracted. The Vulkan module loads only where Vulkan 1.1 exists (API 28+);
    // elsewhere the CPU module serves alone (sdd-flutter-llama-agent 1.2).
    static bool backends_loaded = false;
    if (!backends_loaded) {
        for (const char* name : {"libggml-cpu.so", "libggml-vulkan.so", "libggml-opencl.so"}) {
            if (ggml_backend_load(name)) LOGI("backend module loaded: %s", name);
            else LOGI("backend module not available: %s", name);
        }
        for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
            ggml_backend_dev_t dev = ggml_backend_dev_get(i);
            LOGI("device %zu: %s (%s)", i, ggml_backend_dev_name(dev), ggml_backend_dev_description(dev));
        }
        backends_loaded = true;
    }
    
    // Set up model parameters
    llama_model_params model_params = llama_model_default_params();
    // A negative layer count means "auto" (sdd-flutter-llama-agent 1.2, measured 2026-10-10): offload only to GPUs where
    // ggml-vulkan is known to beat the CPU. On a Mali-G57 it ran ~3x slower (2.0 vs 6.5–7.3 tok/s, Qwen3-0.6B), so Mali
    // and PowerVR stay on the CPU; Adreno and others get every layer. A non-negative count is used as given.
    int gpu_layers = use_gpu ? n_gpu_layers : 0;
    if (gpu_layers < 0) {
        bool slow_gpu = false, any_gpu = false;
        for (size_t i = 0; i < ggml_backend_dev_count(); i++) {
            ggml_backend_dev_t dev = ggml_backend_dev_get(i);
            if (ggml_backend_dev_type(dev) != GGML_BACKEND_DEVICE_TYPE_GPU) continue;
            any_gpu = true;
            const std::string desc = ggml_backend_dev_description(dev);
            if (desc.find("Mali") != std::string::npos || desc.find("PowerVR") != std::string::npos) slow_gpu = true;
        }
        gpu_layers = any_gpu && !slow_gpu ? 999 : 0;
        LOGI("GPU layers auto: %d (%s)", gpu_layers, !any_gpu ? "no GPU device" : slow_gpu ? "GPU slower than CPU here" : "offload");
    }
    model_params.n_gpu_layers = gpu_layers;
    
    // Load model
    g_model = llama_model_load_from_file(path, model_params);
    if (!g_model) {
        LOGE("Failed to load model from: %s", path);
        env->ReleaseStringUTFChars(model_path, path);
        return JNI_FALSE;
    }
    
    // Get vocab
    g_vocab = llama_model_get_vocab(g_model);
    
    // Create context
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = context_size;
    ctx_params.n_batch = batch_size;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    
    g_context = llama_init_from_model(g_model, ctx_params);
    if (!g_context) {
        LOGE("Failed to create context");
        llama_free_model(g_model);
        g_model = nullptr;
        env->ReleaseStringUTFChars(model_path, path);
        return JNI_FALSE;
    }
    
    // Initialize sampler chain
    auto sparams = llama_sampler_chain_default_params();
    sparams.no_perf = false;
    g_sampler = llama_sampler_chain_init(sparams);
    
    // Add samplers
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(0.8f));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    LOGI("Model loaded successfully");
    LOGI("Context size: %d", llama_n_ctx(g_context));
    
    env->ReleaseStringUTFChars(model_path, path);
    return JNI_TRUE;
}

// Generate text
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerate(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context || !g_vocab) {
        LOGE("Model not loaded");
        return nullptr;
    }

    // Clear the KV cache before decoding. The full bounded history is already
    // re-sent in the prompt every turn, so a persistent cache would duplicate
    // that history and overflow the context (ggml_abort). Clearing here on the
    // worker thread also avoids blocking the Flutter main thread (unlike a
    // separate clearContext method-channel call).
    {
        llama_memory_t mem = llama_get_memory(g_context);
        if (mem) {
            llama_memory_clear(mem, true);
        }
    }
    g_should_stop = false;

    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    LOGI("Generating with prompt: %.50s...", prompt_str);
    
    std::string prompt_text(prompt_str);
    env->ReleaseStringUTFChars(prompt, prompt_str);
    
    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);
    
    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        LOGE("Failed to tokenize prompt");
        return nullptr;
    }
    
    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());
    
    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        LOGE("Failed to decode prompt");
        return nullptr;
    }
    
    // Update sampler with new parameters
    llama_sampler_free(g_sampler);
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Generate tokens
    std::string result;
    int n_generated = 0;
    int n_pos = prompt_tokens.size();
    
    g_should_stop = false;
    
    for (int i = 0; i < max_tokens; i++) {
        if (g_should_stop) {
            LOGI("Generation stopped by user");
            break;
        }
        
        // Sample next token
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
        
        // Check for EOS
        if (llama_vocab_is_eog(g_vocab, new_token)) {
            LOGI("EOS token reached");
            break;
        }
        
        // Convert token to text
        char token_str[256] = {0};
        int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
        if (n > 0) {
            token_str[n] = '\0';
            result.append(token_str);
        }
        
        // Prepare for next iteration
        batch = llama_batch_get_one(&new_token, 1);
        n_pos++;
        
        if (llama_decode(g_context, batch) != 0) {
            LOGE("Failed to decode token");
            break;
        }
        
        n_generated++;
    }
    
    LOGI("Generated %d tokens", n_generated);
    
    // Create GenerationResult object
    jclass result_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$GenerationResult");
    if (!result_class) {
        LOGE("Failed to find GenerationResult class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(result_class, "<init>", "(Ljava/lang/String;I)V");
    if (!constructor) {
        LOGE("Failed to find GenerationResult constructor");
        return nullptr;
    }
    
    jstring j_result = env->NewStringUTF(result.c_str());
    jobject generation_result = env->NewObject(result_class, constructor, j_result, n_generated);
    
    return generation_result;
}

// Initialize streaming generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamInit(
    JNIEnv* env,
    jobject thiz,
    jstring prompt,
    jfloat temperature,
    jfloat top_p,
    jint top_k,
    jint max_tokens,
    jfloat repeat_penalty
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Initializing stream generation");
    
    if (!g_model || !g_context || !g_vocab) {
        LOGE("Model not loaded");
        return;
    }
    
    g_should_stop = false;
    g_stream_tokens.clear();
    g_stream_pos = 0;
    
    const char* prompt_str = env->GetStringUTFChars(prompt, nullptr);
    std::string prompt_text(prompt_str);
    env->ReleaseStringUTFChars(prompt, prompt_str);
    
    // Tokenize prompt
    const int n_prompt = -llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), NULL, 0, true, true);
    std::vector<llama_token> prompt_tokens(n_prompt);
    
    if (llama_tokenize(g_vocab, prompt_text.c_str(), prompt_text.size(), prompt_tokens.data(), prompt_tokens.size(), true, true) < 0) {
        LOGE("Failed to tokenize prompt");
        return;
    }
    
    // Create batch
    llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());
    
    // Decode prompt
    if (llama_decode(g_context, batch) != 0) {
        LOGE("Failed to decode prompt");
        return;
    }
    
    // Update sampler
    if (g_sampler) {
        llama_sampler_free(g_sampler);
    }
    
    auto sparams = llama_sampler_chain_default_params();
    g_sampler = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_p(top_p, 1));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_top_k(top_k));
    llama_sampler_chain_add(g_sampler, llama_sampler_init_dist(1234));
    
    // Pre-generate tokens and convert to strings
    int n_pos = prompt_tokens.size();
    for (int i = 0; i < max_tokens; i++) {
        if (g_should_stop) break;
        
        llama_token new_token = llama_sampler_sample(g_sampler, g_context, -1);
        
        if (llama_vocab_is_eog(g_vocab, new_token)) {
            break;
        }
        
        // Convert token to text and store
        char token_str[256] = {0};
        int n = llama_token_to_piece(g_vocab, new_token, token_str, sizeof(token_str) - 1, 0, true);
        if (n > 0) {
            token_str[n] = '\0';
            g_stream_tokens.push_back(std::string(token_str));
        }
        
        batch = llama_batch_get_one(&new_token, 1);
        n_pos++;
        
        if (llama_decode(g_context, batch) != 0) {
            break;
        }
    }
    
    LOGI("Pre-generated %zu tokens for streaming", g_stream_tokens.size());
}

// Get next token in stream
JNIEXPORT jstring JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamNext(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (g_should_stop || g_stream_pos >= g_stream_tokens.size()) {
        return nullptr;
    }
    
    const std::string& token = g_stream_tokens[g_stream_pos++];
    return env->NewStringUTF(token.c_str());
}

// End streaming generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGenerateStreamEnd(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Ending stream generation");
    g_stream_tokens.clear();
    g_stream_pos = 0;
}

// Get model information
JNIEXPORT jobject JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeGetModelInfo(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!g_model || !g_context) {
        return nullptr;
    }
    
    jlong n_params = llama_model_n_params(g_model);
    jint n_layers = llama_model_n_layer(g_model);
    jint context_size = llama_n_ctx(g_context);
    
    LOGI("Model info: params=%lld, layers=%d, context=%d", 
         (long long)n_params, n_layers, context_size);
    
    // Create ModelInfo object
    jclass info_class = env->FindClass("net/nativemind/flutter_llama/FlutterLlamaPlugin$ModelInfo");
    if (!info_class) {
        LOGE("Failed to find ModelInfo class");
        return nullptr;
    }
    
    jmethodID constructor = env->GetMethodID(info_class, "<init>", "(JII)V");
    if (!constructor) {
        LOGE("Failed to find ModelInfo constructor");
        return nullptr;
    }
    
    jobject model_info = env->NewObject(info_class, constructor, n_params, n_layers, context_size);
    return model_info;
}

// Free model
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeFreeModel(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);
    
    LOGI("Freeing model");
    
    if (g_sampler) {
        llama_sampler_free(g_sampler);
        g_sampler = nullptr;
    }
    
    if (g_context) {
        llama_free(g_context);
        g_context = nullptr;
    }
    
    if (g_model) {
        llama_free_model(g_model);
        g_model = nullptr;
    }
    
    g_vocab = nullptr;
    
    LOGI("Model freed successfully");
}

// Stop generation
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeStopGeneration(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    LOGI("Stopping generation");
    g_should_stop = true;
}

// Clear the KV cache so the next generation starts from a fresh context
JNIEXPORT void JNICALL
Java_net_nativemind_flutter_1llama_FlutterLlamaPlugin_nativeClearContext(
    JNIEnv* env,
    jobject thiz
) {
    std::lock_guard<std::mutex> lock(g_mutex);

    LOGI("Clearing KV cache");
    if (g_context) {
        llama_memory_t mem = llama_get_memory(g_context);
        if (mem) {
            llama_memory_clear(mem, true);
        }
    }
    g_should_stop = false;
}

} // extern "C"
