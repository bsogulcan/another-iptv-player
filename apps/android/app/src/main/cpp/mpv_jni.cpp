// JNI bridge between Kotlin `MPVLib` and media-kit's prebuilt libmpv.so.
//
// The threading model mirrors iOS (`MPVPlayer.swift`):
//   - libmpv's wakeup callback fires on an mpv-internal thread; it MUST NOT
//     touch JNI from there. We just signal a condition variable.
//   - One dedicated drain thread per handle is `AttachCurrentThreadAsDaemon`
//     to the JVM and pumps `mpv_wait_event` in a loop whenever the condvar is
//     signalled, dispatching each event to the Java `MPVLib.EventListener`.
//   - All other JNI entry points (command, set/get property, observe) are
//     called from arbitrary Kotlin threads. libmpv API is thread-safe, so
//     we just forward.
//
// Surface attachment uses `wid` (window-id) with `gpu-context=android`; libmpv
// internally manages EGL against the `ANativeWindow*`. We never touch GL.

#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>

#include <atomic>
#include <condition_variable>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include <mpv/client.h>

// libmpv on Android doesn't ship its own `JNI_OnLoad`; without one, the
// `vo/gpu/android` backend can't find a JavaVM and fails with
// `"No Java virtual machine has been registered"` → `"Could not attach java VM"`.
// libmpv exports two registration entry points we link against from our own
// `JNI_OnLoad` below: `mpv_lavc_set_java_vm` (mpv-side) + `av_jni_set_java_vm`
// (FFmpeg-side, needed by `hwdec=mediacodec*`). These prototypes are not in
// `client.h` (it's the public API surface), so we declare them locally.
extern "C" {
void mpv_lavc_set_java_vm(void* vm);
int  av_jni_set_java_vm(void* vm, void* log_ctx);
}

#define LOG_TAG "mpv_jni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ---------------------------------------------------------------------------
// JavaVM + cached EventListener method IDs
// ---------------------------------------------------------------------------

namespace {

JavaVM* g_jvm = nullptr;

struct EventListenerMethods {
  jclass    listenerClass = nullptr;  // global ref
  jmethodID onPropertyChange = nullptr;
  jmethodID onLogMessage = nullptr;
  jmethodID onEndFile = nullptr;
  jmethodID onEvent = nullptr;
};
EventListenerMethods g_listenerMethods;

struct MpvCtx {
  mpv_handle* handle = nullptr;
  // Listener is a global ref to a Java MPVLib.EventListener instance, or null.
  jobject listenerGlobalRef = nullptr;

  // Drain thread plumbing.
  std::thread drainThread;
  std::mutex  wakeMutex;
  std::condition_variable wakeCv;
  std::atomic<bool> woken{false};
  std::atomic<bool> stopRequested{false};
  std::atomic<bool> drainRunning{false};

  // Currently attached Surface, held as a JNI GLOBAL ref so mpv's render
  // thread (which runs `ANativeWindow_fromSurface` itself — see crash log
  // in the bring-up notes) can dereference the jobject from any thread.
  // We pass its raw pointer to mpv via `wid`/`window-id` (media-kit's libmpv
  // expects the Surface jobject pointer there, NOT an ANativeWindow*).
  jobject surfaceGlobalRef = nullptr;
};

// Handle (jlong returned to Kotlin) → MpvCtx mapping. Lets Kotlin pass the
// handle around as an opaque Long without us ever leaking raw pointers across
// the JNI boundary.
std::mutex g_ctxMutex;
std::unordered_map<jlong, std::unique_ptr<MpvCtx>> g_ctxMap;
std::atomic<jlong> g_nextCtxId{1};

MpvCtx* lookupCtx(jlong id) {
  std::lock_guard<std::mutex> guard(g_ctxMutex);
  auto it = g_ctxMap.find(id);
  return it == g_ctxMap.end() ? nullptr : it->second.get();
}

void wakeupCallback(void* userdata) {
  auto* ctx = static_cast<MpvCtx*>(userdata);
  {
    std::lock_guard<std::mutex> lock(ctx->wakeMutex);
    ctx->woken.store(true, std::memory_order_release);
  }
  ctx->wakeCv.notify_one();
}

// `env` must be valid (drain thread is attached). Returns a NewLocalRef
// jstring or `nullptr` for null input.
jstring nullableJString(JNIEnv* env, const char* s) {
  return s ? env->NewStringUTF(s) : nullptr;
}

void dispatchEvent(JNIEnv* env, MpvCtx* ctx, mpv_event* ev) {
  if (!ctx->listenerGlobalRef) return;

  switch (ev->event_id) {
    case MPV_EVENT_PROPERTY_CHANGE:
      env->CallVoidMethod(
          ctx->listenerGlobalRef, g_listenerMethods.onPropertyChange,
          static_cast<jlong>(ev->reply_userdata));
      break;
    case MPV_EVENT_LOG_MESSAGE: {
      auto* lm = static_cast<mpv_event_log_message*>(ev->data);
      jstring lvl    = nullableJString(env, lm->level);
      jstring prefix = nullableJString(env, lm->prefix);
      jstring text   = nullableJString(env, lm->text);
      env->CallVoidMethod(
          ctx->listenerGlobalRef, g_listenerMethods.onLogMessage,
          lvl, prefix, text);
      if (lvl)    env->DeleteLocalRef(lvl);
      if (prefix) env->DeleteLocalRef(prefix);
      if (text)   env->DeleteLocalRef(text);
      break;
    }
    case MPV_EVENT_END_FILE: {
      auto* end = static_cast<mpv_event_end_file*>(ev->data);
      env->CallVoidMethod(
          ctx->listenerGlobalRef, g_listenerMethods.onEndFile,
          static_cast<jint>(end->reason),
          static_cast<jint>(end->error));
      break;
    }
    default:
      // start_file, file_loaded, playback_restart, video_reconfig, shutdown,
      // queue_overflow, idle … all flow through the generic event channel so
      // the Kotlin side can dispatch by id without us hard-coding here.
      env->CallVoidMethod(
          ctx->listenerGlobalRef, g_listenerMethods.onEvent,
          static_cast<jint>(ev->event_id));
      break;
  }

  if (env->ExceptionCheck()) {
    LOGW("EventListener threw; clearing.");
    env->ExceptionDescribe();
    env->ExceptionClear();
  }
}

void drainLoop(MpvCtx* ctx) {
  JNIEnv* env = nullptr;
  JavaVMAttachArgs args{ JNI_VERSION_1_6, "mpv-drain", nullptr };
  if (g_jvm->AttachCurrentThreadAsDaemon(&env, &args) != JNI_OK) {
    LOGE("AttachCurrentThreadAsDaemon failed; drain thread aborting.");
    return;
  }
  ctx->drainRunning.store(true, std::memory_order_release);

  while (!ctx->stopRequested.load(std::memory_order_acquire)) {
    {
      std::unique_lock<std::mutex> lock(ctx->wakeMutex);
      ctx->wakeCv.wait(lock, [&]{
        return ctx->woken.load(std::memory_order_acquire)
            || ctx->stopRequested.load(std::memory_order_acquire);
      });
      ctx->woken.store(false, std::memory_order_release);
    }
    if (ctx->stopRequested.load(std::memory_order_acquire)) break;

    // Mirror iOS `scheduleDrain`: keep pulling until MPV_EVENT_NONE.
    while (true) {
      mpv_event* ev = mpv_wait_event(ctx->handle, 0);
      if (!ev || ev->event_id == MPV_EVENT_NONE) break;
      dispatchEvent(env, ctx, ev);
      if (ev->event_id == MPV_EVENT_SHUTDOWN) {
        // mpv won't generate further events after SHUTDOWN; let the loop
        // exit naturally on the next stopRequested check.
        break;
      }
    }
  }

  g_jvm->DetachCurrentThread();
  ctx->drainRunning.store(false, std::memory_order_release);
}

void stopDrainThread(MpvCtx* ctx) {
  if (!ctx->drainRunning.load(std::memory_order_acquire)) return;
  ctx->stopRequested.store(true, std::memory_order_release);
  {
    std::lock_guard<std::mutex> lock(ctx->wakeMutex);
    ctx->woken.store(true, std::memory_order_release);
  }
  ctx->wakeCv.notify_all();
  if (ctx->drainThread.joinable()) ctx->drainThread.join();
}

}  // anonymous namespace

// ---------------------------------------------------------------------------
// JNI_OnLoad — cache JavaVM + EventListener method IDs once.
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  g_jvm = vm;

  // Register the JVM with libmpv + FFmpeg BEFORE any `mpv_create` call so
  // the Android GPU context and mediacodec hwdec can attach to it. Order
  // doesn't matter between the two; both look at static globals inside
  // libmpv.so. Has to happen in `JNI_OnLoad` (not lazily on first create)
  // because mpv's option parsing inspects the JVM at `mpv_initialize` time.
  mpv_lavc_set_java_vm(vm);
  int avRc = av_jni_set_java_vm(vm, nullptr);
  if (avRc < 0) {
    LOGW("av_jni_set_java_vm failed (rc=%d) — mediacodec hwdec may not work", avRc);
  }

  JNIEnv* env = nullptr;
  if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
    return -1;
  }
  jclass localCls = env->FindClass("dev/android/anotheriptvplayer/player/MPVLib$EventListener");
  if (!localCls) {
    LOGE("MPVLib$EventListener not found");
    return -1;
  }
  g_listenerMethods.listenerClass = static_cast<jclass>(env->NewGlobalRef(localCls));
  env->DeleteLocalRef(localCls);

  g_listenerMethods.onPropertyChange = env->GetMethodID(
      g_listenerMethods.listenerClass, "onPropertyChange", "(J)V");
  g_listenerMethods.onLogMessage = env->GetMethodID(
      g_listenerMethods.listenerClass, "onLogMessage",
      "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V");
  g_listenerMethods.onEndFile = env->GetMethodID(
      g_listenerMethods.listenerClass, "onEndFile", "(II)V");
  g_listenerMethods.onEvent = env->GetMethodID(
      g_listenerMethods.listenerClass, "onEvent", "(I)V");

  if (!g_listenerMethods.onPropertyChange || !g_listenerMethods.onLogMessage
      || !g_listenerMethods.onEndFile || !g_listenerMethods.onEvent) {
    LOGE("Failed to resolve one or more EventListener method IDs");
    return -1;
  }
  return JNI_VERSION_1_6;
}

// ---------------------------------------------------------------------------
// Handle lifecycle
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT jlong JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeCreate(JNIEnv*, jclass) {
  mpv_handle* h = mpv_create();
  if (!h) {
    LOGE("mpv_create failed");
    return 0;
  }
  auto ctx = std::make_unique<MpvCtx>();
  ctx->handle = h;
  mpv_set_wakeup_callback(h, wakeupCallback, ctx.get());

  // The drain thread starts immediately; it'll sit on the condvar until the
  // first wakeup. We need it running before `mpv_initialize` because that
  // call itself emits events (e.g. log messages) we want to capture.
  jlong id = g_nextCtxId.fetch_add(1, std::memory_order_relaxed);
  ctx->drainThread = std::thread(drainLoop, ctx.get());
  {
    std::lock_guard<std::mutex> guard(g_ctxMutex);
    g_ctxMap.emplace(id, std::move(ctx));
  }
  return id;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeInitialize(JNIEnv*, jclass, jlong h) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  return mpv_initialize(ctx->handle);
}

extern "C" JNIEXPORT void JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeTerminateDestroy(JNIEnv* env, jclass, jlong h) {
  std::unique_ptr<MpvCtx> ctx;
  {
    std::lock_guard<std::mutex> guard(g_ctxMutex);
    auto it = g_ctxMap.find(h);
    if (it == g_ctxMap.end()) return;
    ctx = std::move(it->second);
    g_ctxMap.erase(it);
  }

  // Order matters: unhook the wakeup before tearing down the drain thread,
  // otherwise an in-flight callback could try to signal a destroyed condvar.
  mpv_set_wakeup_callback(ctx->handle, nullptr, nullptr);
  stopDrainThread(ctx.get());

  // Tell mpv to release the surface BEFORE we drop our global ref; otherwise
  // a frame already in flight could deref the jobject after we've freed it.
  int64_t zero = 0;
  mpv_set_property(ctx->handle, "wid", MPV_FORMAT_INT64, &zero);
  mpv_terminate_destroy(ctx->handle);

  if (ctx->surfaceGlobalRef) {
    env->DeleteGlobalRef(ctx->surfaceGlobalRef);
    ctx->surfaceGlobalRef = nullptr;
  }
  if (ctx->listenerGlobalRef) {
    env->DeleteGlobalRef(ctx->listenerGlobalRef);
    ctx->listenerGlobalRef = nullptr;
  }
  // ctx goes out of scope and frees.
}

extern "C" JNIEXPORT jstring JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeErrorString(JNIEnv* env, jclass, jint code) {
  return env->NewStringUTF(mpv_error_string(code));
}

// ---------------------------------------------------------------------------
// Event listener registration
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT void JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetEventListener(
    JNIEnv* env, jclass, jlong h, jobject listener) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return;
  if (ctx->listenerGlobalRef) {
    env->DeleteGlobalRef(ctx->listenerGlobalRef);
    ctx->listenerGlobalRef = nullptr;
  }
  if (listener) {
    ctx->listenerGlobalRef = env->NewGlobalRef(listener);
  }
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeRequestLogMessages(
    JNIEnv* env, jclass, jlong h, jstring jLevel) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* level = env->GetStringUTFChars(jLevel, nullptr);
  jint st = mpv_request_log_messages(ctx->handle, level);
  env->ReleaseStringUTFChars(jLevel, level);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeObserveProperty(
    JNIEnv* env, jclass, jlong h, jlong replyId, jstring jName, jint format) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  jint st = mpv_observe_property(
      ctx->handle, static_cast<uint64_t>(replyId), name,
      static_cast<mpv_format>(format));
  env->ReleaseStringUTFChars(jName, name);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeUnobserveProperty(
    JNIEnv*, jclass, jlong h, jlong replyId) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  return mpv_unobserve_property(ctx->handle, static_cast<uint64_t>(replyId));
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeCommand(
    JNIEnv* env, jclass, jlong h, jobjectArray jArgs) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;

  jsize n = env->GetArrayLength(jArgs);
  std::vector<std::string> owned;
  owned.reserve(static_cast<size_t>(n));
  std::vector<const char*> argv;
  argv.reserve(static_cast<size_t>(n) + 1);
  for (jsize i = 0; i < n; i++) {
    auto js = static_cast<jstring>(env->GetObjectArrayElement(jArgs, i));
    const char* cs = env->GetStringUTFChars(js, nullptr);
    owned.emplace_back(cs);
    env->ReleaseStringUTFChars(js, cs);
    env->DeleteLocalRef(js);
    argv.push_back(owned.back().c_str());
  }
  argv.push_back(nullptr);

  return mpv_command(ctx->handle, argv.data());
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeCommandString(
    JNIEnv* env, jclass, jlong h, jstring jCmd) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* cmd = env->GetStringUTFChars(jCmd, nullptr);
  jint st = mpv_command_string(ctx->handle, cmd);
  env->ReleaseStringUTFChars(jCmd, cmd);
  return st;
}

// ---------------------------------------------------------------------------
// Options + properties (typed)
// ---------------------------------------------------------------------------

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetOptionString(
    JNIEnv* env, jclass, jlong h, jstring jName, jstring jValue) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name  = env->GetStringUTFChars(jName, nullptr);
  const char* value = env->GetStringUTFChars(jValue, nullptr);
  jint st = mpv_set_option_string(ctx->handle, name, value);
  env->ReleaseStringUTFChars(jName, name);
  env->ReleaseStringUTFChars(jValue, value);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetPropertyString(
    JNIEnv* env, jclass, jlong h, jstring jName, jstring jValue) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name  = env->GetStringUTFChars(jName, nullptr);
  const char* value = env->GetStringUTFChars(jValue, nullptr);
  jint st = mpv_set_property_string(ctx->handle, name, value);
  env->ReleaseStringUTFChars(jName, name);
  env->ReleaseStringUTFChars(jValue, value);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetPropertyDouble(
    JNIEnv* env, jclass, jlong h, jstring jName, jdouble value) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  double v = value;
  jint st = mpv_set_property(ctx->handle, name, MPV_FORMAT_DOUBLE, &v);
  env->ReleaseStringUTFChars(jName, name);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetPropertyLong(
    JNIEnv* env, jclass, jlong h, jstring jName, jlong value) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  int64_t v = value;
  jint st = mpv_set_property(ctx->handle, name, MPV_FORMAT_INT64, &v);
  env->ReleaseStringUTFChars(jName, name);
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeSetPropertyBoolean(
    JNIEnv* env, jclass, jlong h, jstring jName, jboolean value) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  int flag = value ? 1 : 0;
  jint st = mpv_set_property(ctx->handle, name, MPV_FORMAT_FLAG, &flag);
  env->ReleaseStringUTFChars(jName, name);
  return st;
}

// Read-side: return nullable Java wrappers so Kotlin can `?.` chain without
// caring whether mpv reported "property unavailable" vs a hard error.

extern "C" JNIEXPORT jstring JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeGetPropertyString(
    JNIEnv* env, jclass, jlong h, jstring jName) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return nullptr;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  char* result = mpv_get_property_string(ctx->handle, name);
  env->ReleaseStringUTFChars(jName, name);
  if (!result) return nullptr;
  jstring js = env->NewStringUTF(result);
  mpv_free(result);
  return js;
}

namespace {
jobject boxDouble(JNIEnv* env, double v) {
  jclass cls = env->FindClass("java/lang/Double");
  jmethodID ctor = env->GetMethodID(cls, "<init>", "(D)V");
  jobject obj = env->NewObject(cls, ctor, v);
  env->DeleteLocalRef(cls);
  return obj;
}
jobject boxLong(JNIEnv* env, int64_t v) {
  jclass cls = env->FindClass("java/lang/Long");
  jmethodID ctor = env->GetMethodID(cls, "<init>", "(J)V");
  jobject obj = env->NewObject(cls, ctor, static_cast<jlong>(v));
  env->DeleteLocalRef(cls);
  return obj;
}
jobject boxBoolean(JNIEnv* env, bool v) {
  jclass cls = env->FindClass("java/lang/Boolean");
  jmethodID ctor = env->GetMethodID(cls, "<init>", "(Z)V");
  jobject obj = env->NewObject(cls, ctor, static_cast<jboolean>(v));
  env->DeleteLocalRef(cls);
  return obj;
}
}  // namespace

extern "C" JNIEXPORT jobject JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeGetPropertyDouble(
    JNIEnv* env, jclass, jlong h, jstring jName) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return nullptr;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  double v = 0;
  int st = mpv_get_property(ctx->handle, name, MPV_FORMAT_DOUBLE, &v);
  env->ReleaseStringUTFChars(jName, name);
  return st < 0 ? nullptr : boxDouble(env, v);
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeGetPropertyLong(
    JNIEnv* env, jclass, jlong h, jstring jName) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return nullptr;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  int64_t v = 0;
  int st = mpv_get_property(ctx->handle, name, MPV_FORMAT_INT64, &v);
  env->ReleaseStringUTFChars(jName, name);
  return st < 0 ? nullptr : boxLong(env, v);
}

extern "C" JNIEXPORT jobject JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeGetPropertyBoolean(
    JNIEnv* env, jclass, jlong h, jstring jName) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return nullptr;
  const char* name = env->GetStringUTFChars(jName, nullptr);
  int flag = 0;
  int st = mpv_get_property(ctx->handle, name, MPV_FORMAT_FLAG, &flag);
  env->ReleaseStringUTFChars(jName, name);
  return st < 0 ? nullptr : boxBoolean(env, flag != 0);
}

// ---------------------------------------------------------------------------
// Surface attachment
// ---------------------------------------------------------------------------
//
// media-kit's libmpv (vo=gpu, gpu-context=android) reads the `wid` int64
// option as the address of a Java `Surface` *jobject* — it calls
// `ANativeWindow_fromSurface(env, (jobject)wid)` on its own render thread.
//
// We had originally converted the Surface to an ANativeWindow* ourselves and
// passed that pointer; that crashed inside libmpv with
// `JNI ERROR: jobject is an invalid JNI transition frame reference` because
// mpv re-interpreted the raw window pointer as a Java reference. The correct
// pattern is to hold a JNI *global* ref to the Surface (so it stays valid
// across threads) and hand mpv the global ref's raw address.

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeAttachSurface(
    JNIEnv* env, jclass, jlong h, jobject surface) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;

  // Detach any previous surface first. Setting wid to 0 makes mpv release
  // its hold on the old jobject; doing this before we drop the old global
  // ref avoids a race with mpv's render thread still calling
  // ANativeWindow_fromSurface on the about-to-be-deleted ref.
  if (ctx->surfaceGlobalRef) {
    int64_t zero = 0;
    mpv_set_property(ctx->handle, "wid", MPV_FORMAT_INT64, &zero);
    env->DeleteGlobalRef(ctx->surfaceGlobalRef);
    ctx->surfaceGlobalRef = nullptr;
  }

  if (!surface) {
    LOGE("nativeAttachSurface called with null surface");
    return MPV_ERROR_INVALID_PARAMETER;
  }
  jobject globalRef = env->NewGlobalRef(surface);
  if (!globalRef) {
    LOGE("NewGlobalRef(surface) returned null");
    return MPV_ERROR_GENERIC;
  }
  ctx->surfaceGlobalRef = globalRef;

  int64_t wid = static_cast<int64_t>(reinterpret_cast<intptr_t>(globalRef));
  int st = mpv_set_property(ctx->handle, "wid", MPV_FORMAT_INT64, &wid);
  if (st < 0) {
    LOGE("set wid failed: %d (%s)", st, mpv_error_string(st));
    env->DeleteGlobalRef(ctx->surfaceGlobalRef);
    ctx->surfaceGlobalRef = nullptr;
  }
  return st;
}

extern "C" JNIEXPORT jint JNICALL
Java_dev_android_anotheriptvplayer_player_MPVLib_nativeDetachSurface(
    JNIEnv* env, jclass, jlong h) {
  auto* ctx = lookupCtx(h);
  if (!ctx) return MPV_ERROR_INVALID_PARAMETER;
  int64_t wid = 0;
  int st = mpv_set_property(ctx->handle, "wid", MPV_FORMAT_INT64, &wid);
  if (ctx->surfaceGlobalRef) {
    env->DeleteGlobalRef(ctx->surfaceGlobalRef);
    ctx->surfaceGlobalRef = nullptr;
  }
  return st;
}
