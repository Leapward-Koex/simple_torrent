#include "simple_torrent_native.h"

#include <jni.h>

#include <codecvt>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <locale>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {

std::mutex g_ssl_environment_mutex;

struct AndroidManager {
  JavaVM* vm = nullptr;
  jobject plugin = nullptr;
  jmethodID dispatch_stats = nullptr;
  jmethodID dispatch_metadata = nullptr;
  simple_torrent_manager_t* manager = nullptr;
};

class ScopedEnv {
 public:
  explicit ScopedEnv(JavaVM* vm) : vm_(vm) {
    if (vm_->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6) ==
        JNI_EDETACHED) {
      if (vm_->AttachCurrentThread(&env_, nullptr) == JNI_OK) {
        attached_ = true;
      } else {
        env_ = nullptr;
      }
    }
  }
  ~ScopedEnv() {
    if (attached_) {
      vm_->DetachCurrentThread();
    }
  }
  JNIEnv* get() const { return env_; }

 private:
  JavaVM* vm_;
  JNIEnv* env_ = nullptr;
  bool attached_ = false;
};

std::string FromJavaString(JNIEnv* env, jstring value) {
  if (value == nullptr) {
    return {};
  }
  const auto* chars = env->GetStringChars(value, nullptr);
  if (chars == nullptr) {
    return {};
  }
  const auto length = env->GetStringLength(value);
  std::u16string utf16(reinterpret_cast<const char16_t*>(chars),
                       static_cast<std::size_t>(length));
  env->ReleaseStringChars(value, chars);
  try {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>
        converter;
    return converter.to_bytes(utf16);
  } catch (...) {
    return {};
  }
}

bool HasEmbeddedNull(const std::string& value) {
  return value.find('\0') != std::string::npos;
}

jstring ToJavaString(JNIEnv* env, const char* value) {
  if (value == nullptr) {
    value = "";
  }
  try {
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>
        converter;
    const auto utf16 = converter.from_bytes(value);
    return env->NewString(reinterpret_cast<const jchar*>(utf16.data()),
                          static_cast<jsize>(utf16.size()));
  } catch (...) {
    return env->NewStringUTF("");
  }
}

jobject NewMap(JNIEnv* env) {
  const auto map_class = env->FindClass("java/util/HashMap");
  const auto constructor = env->GetMethodID(map_class, "<init>", "()V");
  auto map = env->NewObject(map_class, constructor);
  env->DeleteLocalRef(map_class);
  return map;
}

void MapPut(JNIEnv* env, jobject map, const char* key, jobject value) {
  const auto map_class = env->GetObjectClass(map);
  const auto put = env->GetMethodID(
      map_class, "put",
      "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
  const auto java_key = env->NewStringUTF(key);
  const auto previous = env->CallObjectMethod(map, put, java_key, value);
  if (previous != nullptr) {
    env->DeleteLocalRef(previous);
  }
  env->DeleteLocalRef(java_key);
  env->DeleteLocalRef(map_class);
  env->DeleteLocalRef(value);
}

jobject BoxInt(JNIEnv* env, jint value) {
  const auto type = env->FindClass("java/lang/Integer");
  const auto value_of =
      env->GetStaticMethodID(type, "valueOf", "(I)Ljava/lang/Integer;");
  auto result = env->CallStaticObjectMethod(type, value_of, value);
  env->DeleteLocalRef(type);
  return result;
}

jobject BoxLong(JNIEnv* env, jlong value) {
  const auto type = env->FindClass("java/lang/Long");
  const auto value_of =
      env->GetStaticMethodID(type, "valueOf", "(J)Ljava/lang/Long;");
  auto result = env->CallStaticObjectMethod(type, value_of, value);
  env->DeleteLocalRef(type);
  return result;
}

jobject BoxDouble(JNIEnv* env, jdouble value) {
  const auto type = env->FindClass("java/lang/Double");
  const auto value_of =
      env->GetStaticMethodID(type, "valueOf", "(D)Ljava/lang/Double;");
  auto result = env->CallStaticObjectMethod(type, value_of, value);
  env->DeleteLocalRef(type);
  return result;
}

jobject BoxBool(JNIEnv* env, bool value) {
  const auto type = env->FindClass("java/lang/Boolean");
  const auto value_of =
      env->GetStaticMethodID(type, "valueOf", "(Z)Ljava/lang/Boolean;");
  auto result = env->CallStaticObjectMethod(
      type, value_of, static_cast<jboolean>(value));
  env->DeleteLocalRef(type);
  return result;
}

jobject MapGet(JNIEnv* env, jobject map, const char* key) {
  const auto map_class = env->GetObjectClass(map);
  const auto get = env->GetMethodID(
      map_class, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
  const auto java_key = env->NewStringUTF(key);
  auto value = env->CallObjectMethod(map, get, java_key);
  env->DeleteLocalRef(java_key);
  env->DeleteLocalRef(map_class);
  return value;
}

bool MapContains(JNIEnv* env, jobject map, const char* key) {
  const auto map_class = env->GetObjectClass(map);
  const auto contains = env->GetMethodID(
      map_class, "containsKey", "(Ljava/lang/Object;)Z");
  const auto java_key = env->NewStringUTF(key);
  const auto result =
      env->CallBooleanMethod(map, contains, java_key) == JNI_TRUE;
  env->DeleteLocalRef(java_key);
  env->DeleteLocalRef(map_class);
  return result;
}

bool ReadLong(JNIEnv* env, jobject map, const char* key, std::int64_t* value) {
  auto object = MapGet(env, map, key);
  if (object == nullptr) {
    return false;
  }
  const auto integer_class = env->FindClass("java/lang/Integer");
  const auto long_class = env->FindClass("java/lang/Long");
  const auto is_integer = env->IsInstanceOf(object, integer_class);
  const auto is_long = env->IsInstanceOf(object, long_class);
  if (is_integer || is_long) {
    const auto number_class = env->FindClass("java/lang/Number");
    const auto long_value =
        env->GetMethodID(number_class, "longValue", "()J");
    *value = env->CallLongMethod(object, long_value);
    env->DeleteLocalRef(number_class);
  }
  env->DeleteLocalRef(integer_class);
  env->DeleteLocalRef(long_class);
  env->DeleteLocalRef(object);
  return is_integer || is_long;
}

bool ReadBool(JNIEnv* env, jobject map, const char* key, bool* value) {
  auto object = MapGet(env, map, key);
  if (object == nullptr) {
    return false;
  }
  const auto bool_class = env->FindClass("java/lang/Boolean");
  const auto is_bool = env->IsInstanceOf(object, bool_class);
  if (is_bool) {
    const auto bool_value =
        env->GetMethodID(bool_class, "booleanValue", "()Z");
    *value = env->CallBooleanMethod(object, bool_value) == JNI_TRUE;
  }
  env->DeleteLocalRef(bool_class);
  env->DeleteLocalRef(object);
  return is_bool;
}

bool ReadString(JNIEnv* env, jobject map, const char* key, std::string* value) {
  auto object = MapGet(env, map, key);
  if (object == nullptr) {
    return false;
  }
  const auto string_class = env->FindClass("java/lang/String");
  const auto is_string = env->IsInstanceOf(object, string_class);
  if (is_string) {
    *value = FromJavaString(env, static_cast<jstring>(object));
  }
  env->DeleteLocalRef(string_class);
  env->DeleteLocalRef(object);
  return is_string;
}

simple_torrent_result_t ConfigFromMap(JNIEnv* env,
                                      jobject map,
                                      simple_torrent_config_t* config,
                                      std::string* user_agent) {
  simple_torrent_config_init(config);
  *user_agent = config->user_agent;
  if (map == nullptr) {
    config->user_agent = user_agent->c_str();
    return SIMPLE_TORRENT_OK;
  }

  std::int64_t number = 0;
  bool boolean = false;
  if (MapContains(env, map, "maxTorrents")) {
    if (!ReadLong(env, map, "maxTorrents", &number) ||
        number < std::numeric_limits<std::int32_t>::min() ||
        number > std::numeric_limits<std::int32_t>::max()) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->max_torrents = static_cast<std::int32_t>(number);
  }
  if (MapContains(env, map, "downloadRateLimit")) {
    if (!ReadLong(env, map, "downloadRateLimit", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->download_rate_limit = number;
  }
  if (MapContains(env, map, "uploadRateLimit")) {
    if (!ReadLong(env, map, "uploadRateLimit", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->upload_rate_limit = number;
  }
  if (MapContains(env, map, "connectionsLimit")) {
    if (!ReadLong(env, map, "connectionsLimit", &number) ||
        number < std::numeric_limits<std::int32_t>::min() ||
        number > std::numeric_limits<std::int32_t>::max()) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->connections_limit = static_cast<std::int32_t>(number);
  }
  if (MapContains(env, map, "enableDht")) {
    if (!ReadBool(env, map, "enableDht", &boolean)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->enable_dht = static_cast<std::uint8_t>(boolean);
  }
  if (MapContains(env, map, "userAgent") &&
      !ReadString(env, map, "userAgent", user_agent)) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  if (HasEmbeddedNull(*user_agent)) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  config->user_agent = user_agent->c_str();
  return SIMPLE_TORRENT_OK;
}

void StatsCallback(void* user_data,
                   const simple_torrent_stats_t* stats) try {
  auto* android_manager = static_cast<AndroidManager*>(user_data);
  ScopedEnv scoped_env(android_manager->vm);
  auto* env = scoped_env.get();
  if (env == nullptr || stats == nullptr) {
    return;
  }

  auto map = NewMap(env);
  MapPut(env, map, "eventType", ToJavaString(env, "stats"));
  MapPut(env, map, "id", BoxInt(env, stats->id));
  MapPut(env, map, "download_rate", BoxLong(env, stats->download_rate));
  MapPut(env, map, "upload_rate", BoxLong(env, stats->upload_rate));
  MapPut(env, map, "pieces", BoxInt(env, stats->pieces));
  MapPut(env, map, "pieces_total", BoxInt(env, stats->pieces_total));
  MapPut(env, map, "progress", BoxDouble(env, stats->progress));
  MapPut(env, map, "seeds", BoxInt(env, stats->seeds));
  MapPut(env, map, "peers", BoxInt(env, stats->peers));
  MapPut(env, map, "state",
         ToJavaString(env, simple_torrent_state_name(stats->state)));
  env->CallVoidMethod(android_manager->plugin,
                      android_manager->dispatch_stats, map);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  env->DeleteLocalRef(map);
} catch (...) {
  // JNI callbacks are exception barriers for the native polling thread.
}

void MetadataCallback(void* user_data,
                      const simple_torrent_metadata_t* metadata) try {
  auto* android_manager = static_cast<AndroidManager*>(user_data);
  ScopedEnv scoped_env(android_manager->vm);
  auto* env = scoped_env.get();
  if (env == nullptr || metadata == nullptr) {
    return;
  }

  auto map = NewMap(env);
  MapPut(env, map, "eventType", ToJavaString(env, "metadata"));
  MapPut(env, map, "id", BoxInt(env, metadata->id));
  MapPut(env, map, "name", ToJavaString(env, metadata->name));
  MapPut(env, map, "total_bytes", BoxLong(env, metadata->total_bytes));
  MapPut(env, map, "piece_size", BoxInt(env, metadata->piece_size));
  MapPut(env, map, "piece_count", BoxInt(env, metadata->piece_count));
  MapPut(env, map, "file_count", BoxInt(env, metadata->file_count));
  MapPut(env, map, "creation_date", BoxLong(env, metadata->creation_date));
  MapPut(env, map, "private", BoxBool(env, metadata->is_private != 0));
  MapPut(env, map, "v2", BoxBool(env, metadata->is_v2 != 0));
  MapPut(env, map, "v1_info_hash",
         ToJavaString(env, metadata->v1_info_hash));
  MapPut(env, map, "v2_info_hash",
         ToJavaString(env, metadata->v2_info_hash));

  const auto list_class = env->FindClass("java/util/ArrayList");
  const auto list_constructor = env->GetMethodID(list_class, "<init>", "()V");
  const auto list_add =
      env->GetMethodID(list_class, "add", "(Ljava/lang/Object;)Z");
  auto files = env->NewObject(list_class, list_constructor);
  for (std::size_t index = 0; index < metadata->files_count; ++index) {
    const auto& file = metadata->files[index];
    auto file_map = NewMap(env);
    MapPut(env, file_map, "index", BoxInt(env, file.index));
    MapPut(env, file_map, "path", ToJavaString(env, file.path));
    MapPut(env, file_map, "size", BoxLong(env, file.size));
    MapPut(env, file_map, "offset", BoxLong(env, file.offset));
    env->CallBooleanMethod(files, list_add, file_map);
    env->DeleteLocalRef(file_map);
  }
  env->DeleteLocalRef(list_class);
  MapPut(env, map, "files", files);

  env->CallVoidMethod(android_manager->plugin,
                      android_manager->dispatch_metadata, map);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  env->DeleteLocalRef(map);
} catch (...) {
  // JNI callbacks are exception barriers for the native polling thread.
}

AndroidManager* FromHandle(jlong handle) {
  return reinterpret_cast<AndroidManager*>(static_cast<std::intptr_t>(handle));
}

jintArray StartResult(JNIEnv* env,
                      simple_torrent_result_t result,
                      std::int32_t id) {
  const jint values[] = {static_cast<jint>(result), static_cast<jint>(id)};
  auto array = env->NewIntArray(2);
  if (array == nullptr) {
    return nullptr;
  }
  env->SetIntArrayRegion(array, 0, 2, values);
  return array;
}

// Query JNI calls all use the same result envelope so a valid domain value
// (for example false or an empty list) cannot be confused with a native error.
jobject QueryResult(JNIEnv* env,
                    simple_torrent_result_t result,
                    jobject value = nullptr) {
  auto map = NewMap(env);
  MapPut(env, map, "code", BoxInt(env, static_cast<jint>(result)));
  if (value != nullptr) {
    MapPut(env, map, "value", value);
  }
  return map;
}

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeCreate(
    JNIEnv* env,
    jobject plugin,
    jobject config_map,
    jstring ca_bundle_path) try {
  auto manager = std::make_unique<AndroidManager>();
  if (env->GetJavaVM(&manager->vm) != JNI_OK) {
    return 0;
  }
  manager->plugin = env->NewGlobalRef(plugin);
  const auto plugin_class = env->GetObjectClass(plugin);
  manager->dispatch_stats = env->GetMethodID(
      plugin_class, "dispatchStatsFromNative", "(Ljava/util/Map;)V");
  manager->dispatch_metadata = env->GetMethodID(
      plugin_class, "dispatchMetadataFromNative", "(Ljava/util/Map;)V");
  env->DeleteLocalRef(plugin_class);
  if (manager->plugin == nullptr || manager->dispatch_stats == nullptr ||
      manager->dispatch_metadata == nullptr) {
    if (manager->plugin != nullptr) {
      env->DeleteGlobalRef(manager->plugin);
    }
    return 0;
  }

  simple_torrent_config_t config;
  std::string user_agent;
  if (ConfigFromMap(env, config_map, &config, &user_agent) !=
      SIMPLE_TORRENT_OK) {
    env->DeleteGlobalRef(manager->plugin);
    return 0;
  }
  const auto native_ca_bundle_path = FromJavaString(env, ca_bundle_path);
  if (native_ca_bundle_path.empty() ||
      HasEmbeddedNull(native_ca_bundle_path)) {
    env->DeleteGlobalRef(manager->plugin);
    return 0;
  }
  simple_torrent_result_t result = SIMPLE_TORRENT_NATIVE_ERROR;
  {
    // OpenSSL reads SSL_CERT_FILE while libtorrent constructs its session.
    // Serialize the process-global environment update with that construction.
    std::lock_guard environment_lock(g_ssl_environment_mutex);
    if (setenv("SSL_CERT_FILE", native_ca_bundle_path.c_str(), 1) == 0) {
      result = simple_torrent_manager_create(
          &config, StatsCallback, MetadataCallback, manager.get(),
          &manager->manager);
    }
  }
  if (result != SIMPLE_TORRENT_OK) {
    env->DeleteGlobalRef(manager->plugin);
    return 0;
  }
  return static_cast<jlong>(reinterpret_cast<std::intptr_t>(manager.release()));
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return 0;
}

JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeDestroy(
    JNIEnv* env, jobject, jlong handle) try {
  std::unique_ptr<AndroidManager> manager(FromHandle(handle));
  if (!manager) {
    return;
  }
  simple_torrent_manager_destroy(manager->manager);
  manager->manager = nullptr;
  env->DeleteGlobalRef(manager->plugin);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeUpdateConfig(
    JNIEnv* env, jobject, jlong handle, jobject config_map) try {
  auto* manager = FromHandle(handle);
  if (manager == nullptr || config_map == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  simple_torrent_config_t config;
  std::string user_agent;
  const auto conversion = ConfigFromMap(env, config_map, &config, &user_agent);
  if (conversion != SIMPLE_TORRENT_OK) {
    return conversion;
  }
  return simple_torrent_manager_update_config(manager->manager, &config);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeSetTransfersSuspended(
    JNIEnv* env, jobject, jlong handle, jboolean suspended) try {
  auto* manager = FromHandle(handle);
  return manager == nullptr
             ? SIMPLE_TORRENT_INVALID_ARGUMENT
             : simple_torrent_manager_set_transfers_suspended(
                   manager->manager,
                   suspended == JNI_TRUE ? std::uint8_t{1} : std::uint8_t{0});
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeTransfersSuspended(
    JNIEnv* env, jobject, jlong handle) try {
  auto* manager = FromHandle(handle);
  std::uint8_t suspended = 0;
  const auto code = manager == nullptr
                        ? SIMPLE_TORRENT_INVALID_ARGUMENT
                        : simple_torrent_manager_transfers_suspended(
                              manager->manager, &suspended);
  return code == SIMPLE_TORRENT_OK
             ? QueryResult(env, code, BoxBool(env, suspended != 0))
             : QueryResult(env, code);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

JNIEXPORT jintArray JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeStart(
    JNIEnv* env,
    jobject,
    jlong handle,
    jstring magnet,
    jstring destination,
    jstring display_name) try {
  auto* manager = FromHandle(handle);
  if (manager == nullptr) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  const auto native_magnet = FromJavaString(env, magnet);
  const auto native_destination = FromJavaString(env, destination);
  const auto native_display_name = FromJavaString(env, display_name);
  if (HasEmbeddedNull(native_magnet) ||
      HasEmbeddedNull(native_destination) ||
      HasEmbeddedNull(native_display_name)) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  std::int32_t id = 0;
  const auto result = simple_torrent_manager_start(
      manager->manager, native_magnet.c_str(), native_destination.c_str(),
      display_name == nullptr ? nullptr : native_display_name.c_str(), &id);
  return StartResult(env, result, id);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return StartResult(env, SIMPLE_TORRENT_NATIVE_ERROR, 0);
}

JNIEXPORT jintArray JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeStartFromData(
    JNIEnv* env,
    jobject,
    jlong handle,
    jbyteArray data,
    jstring destination,
    jstring display_name) try {
  auto* manager = FromHandle(handle);
  if (manager == nullptr || data == nullptr) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  const auto length = env->GetArrayLength(data);
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
  if (length > 0) {
    env->GetByteArrayRegion(
        data, 0, length, reinterpret_cast<jbyte*>(bytes.data()));
  }
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
    return StartResult(env, SIMPLE_TORRENT_NATIVE_ERROR, 0);
  }
  const auto native_destination = FromJavaString(env, destination);
  const auto native_display_name = FromJavaString(env, display_name);
  if (HasEmbeddedNull(native_destination) ||
      HasEmbeddedNull(native_display_name)) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  std::int32_t id = 0;
  const auto result = simple_torrent_manager_start_from_data(
      manager->manager, bytes.data(), bytes.size(), native_destination.c_str(),
      display_name == nullptr ? nullptr : native_display_name.c_str(), &id);
  return StartResult(env, result, id);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return StartResult(env, SIMPLE_TORRENT_NATIVE_ERROR, 0);
}

JNIEXPORT jintArray JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeStartFromFile(
    JNIEnv* env,
    jobject,
    jlong handle,
    jstring torrent_file_path,
    jstring destination,
    jstring display_name) try {
  auto* manager = FromHandle(handle);
  if (manager == nullptr) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  const auto native_file_path = FromJavaString(env, torrent_file_path);
  const auto native_destination = FromJavaString(env, destination);
  const auto native_display_name = FromJavaString(env, display_name);
  if (HasEmbeddedNull(native_file_path) ||
      HasEmbeddedNull(native_destination) ||
      HasEmbeddedNull(native_display_name)) {
    return StartResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT, 0);
  }
  std::int32_t id = 0;
  const auto result = simple_torrent_manager_start_from_file(
      manager->manager, native_file_path.c_str(), native_destination.c_str(),
      display_name == nullptr ? nullptr : native_display_name.c_str(), &id);
  return StartResult(env, result, id);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return StartResult(env, SIMPLE_TORRENT_NATIVE_ERROR, 0);
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativePause(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  return manager == nullptr ? SIMPLE_TORRENT_INVALID_ARGUMENT
                            : simple_torrent_manager_pause(manager->manager, id);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeResume(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  return manager == nullptr ? SIMPLE_TORRENT_INVALID_ARGUMENT
                            : simple_torrent_manager_resume(manager->manager, id);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeCancel(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  return manager == nullptr ? SIMPLE_TORRENT_INVALID_ARGUMENT
                            : simple_torrent_manager_cancel(manager->manager, id);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeFinalise(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  return manager == nullptr
             ? SIMPLE_TORRENT_INVALID_ARGUMENT
             : simple_torrent_manager_finalise(manager->manager, id);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeActiveIds(
    JNIEnv* env, jobject, jlong handle) try {
  auto* manager = FromHandle(handle);
  if (manager == nullptr) {
    return QueryResult(env, SIMPLE_TORRENT_INVALID_ARGUMENT);
  }
  std::int32_t* ids = nullptr;
  std::size_t count = 0;
  const auto code =
      simple_torrent_manager_active_ids(manager->manager, &ids, &count);
  if (code != SIMPLE_TORRENT_OK) {
    simple_torrent_active_ids_free(ids);
    return QueryResult(env, code);
  }
  if (count > static_cast<std::size_t>(std::numeric_limits<jsize>::max())) {
    simple_torrent_active_ids_free(ids);
    return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
  }
  auto values = env->NewIntArray(static_cast<jsize>(count));
  if (values == nullptr) {
    simple_torrent_active_ids_free(ids);
    if (env->ExceptionCheck()) {
      env->ExceptionClear();
    }
    return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
  }
  if (count != 0) {
    env->SetIntArrayRegion(values, 0, static_cast<jsize>(count), ids);
  }
  simple_torrent_active_ids_free(ids);
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
    env->DeleteLocalRef(values);
    return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
  }
  return QueryResult(env, SIMPLE_TORRENT_OK, values);
} catch (...) {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeExists(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  std::uint8_t exists = 0;
  const auto code = manager == nullptr
                        ? SIMPLE_TORRENT_INVALID_ARGUMENT
                        : simple_torrent_manager_exists(
                              manager->manager, id, &exists);
  return code == SIMPLE_TORRENT_OK
             ? QueryResult(env, code, BoxBool(env, exists != 0))
             : QueryResult(env, code);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeState(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  simple_torrent_state_t state = SIMPLE_TORRENT_STATE_STARTING;
  const auto code = manager == nullptr
                        ? SIMPLE_TORRENT_INVALID_ARGUMENT
                        : simple_torrent_manager_state(
                              manager->manager, id, &state);
  return code == SIMPLE_TORRENT_OK
             ? QueryResult(
                   env, code, ToJavaString(env, simple_torrent_state_name(state)))
             : QueryResult(env, code);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeTorrentInfo(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  simple_torrent_torrent_info_t info{};
  const auto code = manager == nullptr
                        ? SIMPLE_TORRENT_INVALID_ARGUMENT
                        : simple_torrent_manager_torrent_info(
                              manager->manager, id, &info);
  if (code != SIMPLE_TORRENT_OK) {
    return QueryResult(env, code);
  }
  auto map = NewMap(env);
  MapPut(env, map, "id", BoxInt(env, info.id));
  MapPut(env, map, "magnetUri", ToJavaString(env, info.magnet_uri));
  MapPut(env, map, "savePath", ToJavaString(env, info.save_path));
  MapPut(env, map, "displayName", ToJavaString(env, info.display_name));
  MapPut(env, map, "state",
         ToJavaString(env, simple_torrent_state_name(info.state)));
  MapPut(env, map, "lastError", ToJavaString(env, info.last_error));
  MapPut(env, map, "createdAt", BoxLong(env, info.created_at_milliseconds));
  simple_torrent_torrent_info_free(&info);
  return QueryResult(env, SIMPLE_TORRENT_OK, map);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_nativeLastError(
    JNIEnv* env, jobject, jlong handle, jint id) try {
  auto* manager = FromHandle(handle);
  char* error = nullptr;
  const auto code = manager == nullptr
                        ? SIMPLE_TORRENT_INVALID_ARGUMENT
                        : simple_torrent_manager_last_error(
                              manager->manager, id, &error);
  if (code != SIMPLE_TORRENT_OK) {
    return QueryResult(env, code);
  }
  auto value = ToJavaString(env, error);
  simple_torrent_string_free(error);
  return QueryResult(env, SIMPLE_TORRENT_OK, value);
} catch (...) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  return QueryResult(env, SIMPLE_TORRENT_NATIVE_ERROR);
}

}  // extern "C"
