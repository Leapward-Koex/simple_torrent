#include "../../shared/torrent_core/torrent_core.hpp"
#include <jni.h>
#include <mutex>

static JavaVM *g_vm = nullptr;
static jclass g_cls = nullptr;
static jmethodID g_sendStats = nullptr;
static jmethodID g_sendMetadata = nullptr;

static std::mutex g_mtx;
static std::unique_ptr<tc::Manager> g_mgr;

static JNIEnv *attach()
{
    JNIEnv *env = nullptr;
    g_vm->AttachCurrentThread(&env, nullptr);
    return env;
}
static void detach() { g_vm->DetachCurrentThread(); }

static std::string torrentStateToString(tc::TorrentState state)
{
    switch (state)
    {
    case tc::TorrentState::Starting:
        return "starting";
    case tc::TorrentState::DownloadingMetadata:
        return "downloading_metadata";
    case tc::TorrentState::Downloading:
        return "downloading";
    case tc::TorrentState::Seeding:
        return "seeding";
    case tc::TorrentState::Paused:
        return "paused";
    case tc::TorrentState::Error:
        return "error";
    case tc::TorrentState::Stopped:
        return "stopped";
    default:
        return "unknown";
    }
}

static void statsToJava(const tc::Stats &s)
{
    JNIEnv *env = attach();

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID ctor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapCls, "put",
                                     "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID val = env->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");
    
    jclass floatCls = env->FindClass("java/lang/Float");
    jmethodID floatVal = env->GetStaticMethodID(floatCls, "valueOf", "(F)Ljava/lang/Float;");

    auto jintObj = [&](int v)
    { return env->CallStaticObjectMethod(intCls, val, v); };
    
    auto jfloatObj = [&](float v)
    { return env->CallStaticObjectMethod(floatCls, floatVal, v); };

    jobject map = env->NewObject(mapCls, ctor);
#define PUT_STR(key, str)                            \
    {                                                \
        jstring _k = env->NewStringUTF(key);         \
        jstring _v = env->NewStringUTF(str.c_str()); \
        env->CallObjectMethod(map, put, _k, _v);     \
        env->DeleteLocalRef(_k);                     \
        env->DeleteLocalRef(_v);                     \
    }

#define PUT(k, v)                                \
    {                                            \
        jstring _k = env->NewStringUTF(k);       \
        jobject _v = jintObj(v);                 \
        env->CallObjectMethod(map, put, _k, _v); \
        env->DeleteLocalRef(_k);                 \
        env->DeleteLocalRef(_v);                 \
    }

#define PUT_FLOAT(k, v)                          \
    {                                            \
        jstring _k = env->NewStringUTF(k);       \
        jobject _v = jfloatObj(v);               \
        env->CallObjectMethod(map, put, _k, _v); \
        env->DeleteLocalRef(_k);                 \
        env->DeleteLocalRef(_v);                 \
    }

    PUT_STR("eventType", std::string("stats"));
    PUT("id", s.id)
    PUT("download_rate", s.dlRate)
    PUT("upload_rate", s.ulRate)
    PUT("pieces", s.pieces)
    PUT("pieces_total", s.piecesTotal)
    PUT_FLOAT("progress", s.progress)
    PUT("seeds", s.seeds)
    PUT("peers", s.peers)
    PUT_STR("phase", s.phase);
    PUT_STR("state", torrentStateToString(s.state));

#undef PUT
#undef PUT_FLOAT
#undef PUT_STR

    env->CallStaticVoidMethod(g_cls, g_sendStats, map);
    env->DeleteLocalRef(map);
    detach();
}

static void metadataToJava(const tc::Metadata &metadata)
{
    JNIEnv *env = attach();

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID ctor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapCls, "put",
                                     "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID intVal = env->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");

    jclass longCls = env->FindClass("java/lang/Long");
    jmethodID longVal = env->GetStaticMethodID(longCls, "valueOf", "(J)Ljava/lang/Long;");

    jclass boolCls = env->FindClass("java/lang/Boolean");
    jmethodID boolVal = env->GetStaticMethodID(boolCls, "valueOf", "(Z)Ljava/lang/Boolean;");

    auto jintObj = [&](int v)
    { return env->CallStaticObjectMethod(intCls, intVal, v); };
    auto jlongObj = [&](jlong v)
    { return env->CallStaticObjectMethod(longCls, longVal, v); };
    auto jboolObj = [&](bool v)
    { return env->CallStaticObjectMethod(boolCls, boolVal,
                                         static_cast<jboolean>(v)); };

    jobject map = env->NewObject(mapCls, ctor);

#define PUT_NUM(key, valObj)                         \
    {                                                \
        jstring _k = env->NewStringUTF(key);         \
        env->CallObjectMethod(map, put, _k, valObj); \
        env->DeleteLocalRef(_k);                     \
        env->DeleteLocalRef(valObj);                 \
    }

#define PUT_STR(key, str)                            \
    {                                                \
        jstring _k = env->NewStringUTF(key);         \
        jstring _v = env->NewStringUTF(str.c_str()); \
        env->CallObjectMethod(map, put, _k, _v);     \
        env->DeleteLocalRef(_k);                     \
        env->DeleteLocalRef(_v);                     \
    }

    PUT_STR("eventType", std::string("metadata"));

    PUT_NUM("id", jintObj(metadata.id));
    PUT_STR("name", metadata.name);
    PUT_NUM("total_bytes", jlongObj(static_cast<jlong>(metadata.totalBytes)));
    PUT_NUM("piece_size", jintObj(metadata.pieceSize));
    PUT_NUM("piece_count", jintObj(metadata.pieceCount));
    PUT_NUM("file_count", jintObj(metadata.fileCount));
    PUT_NUM("creation_date", jlongObj(static_cast<jlong>(metadata.creationDate)));
    PUT_NUM("private", jboolObj(metadata.isPrivate));
    PUT_NUM("v2", jboolObj(metadata.isV2));

#undef PUT_NUM
#undef PUT_STR

    env->CallStaticVoidMethod(g_cls, g_sendMetadata, map);
    env->DeleteLocalRef(map);
    detach();
}

extern "C" jint JNI_OnLoad(JavaVM *vm, void *)
{
    g_vm = vm;
    JNIEnv *e = nullptr;
    vm->GetEnv((void **)&e, JNI_VERSION_1_6);
    jclass c = e->FindClass("com/leapwardkoex/simple_torrent/simple_torrent/SimpleTorrentPlugin");
    g_cls = (jclass)e->NewGlobalRef(c);

    g_sendStats = e->GetStaticMethodID(g_cls, "sendStats", "(Ljava/util/Map;)V");
    g_sendMetadata = e->GetStaticMethodID(g_cls, "sendMetadata", "(Ljava/util/Map;)V");

    // Initialize with default config
    tc::ManagerConfig config;
    g_mgr = std::make_unique<tc::Manager>(config);
    return JNI_VERSION_1_6;
}

static std::string jstr(JNIEnv *e, jstring s)
{
    const char *c = e->GetStringUTFChars(s, nullptr);
    std::string r(c);
    e->ReleaseStringUTFChars(s, c);
    return r;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_startTorrent(JNIEnv *e, jobject, jstring jMag, jstring jPath)
{
    return g_mgr->start(jstr(e, jMag), jstr(e, jPath), statsToJava, metadataToJava);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_startTorrentWithName(JNIEnv *e, jobject, jstring jMag, jstring jPath, jstring jName)
{
    return g_mgr->start(jstr(e, jMag), jstr(e, jPath), statsToJava, metadataToJava, jstr(e, jName));
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_pauseTorrent(JNIEnv *, jobject, jint id)
{
    g_mgr->pause(id);
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_resumeTorrent(JNIEnv *, jobject, jint id)
{
    g_mgr->resume(id);
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_cancelTorrent(JNIEnv *, jobject, jint id)
{
    g_mgr->cancel(id);
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_finaliseTorrent(JNIEnv *, jobject, jint id)
{
    g_mgr->finalise(id);
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_getActiveTorrentIds(JNIEnv *e, jobject)
{
    auto ids = g_mgr->getActiveTorrentIds();
    jintArray result = e->NewIntArray(ids.size());
    e->SetIntArrayRegion(result, 0, ids.size(), ids.data());
    return result;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_torrentExists(JNIEnv *, jobject, jint id)
{
    return g_mgr->exists(id);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_getTorrentState(JNIEnv *e, jobject, jint id)
{
    tc::TorrentState state = g_mgr->getState(id);
    return e->NewStringUTF(torrentStateToString(state).c_str());
}

extern "C" JNIEXPORT jobject JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_getTorrentInfo(JNIEnv *e, jobject, jint id)
{
    tc::TorrentInfo info = g_mgr->getTorrentInfo(id);

    jclass mapCls = e->FindClass("java/util/HashMap");
    jmethodID ctor = e->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = e->GetMethodID(mapCls, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jobject map = e->NewObject(mapCls, ctor);

    // Helper macros for putting values
    auto putString = [&](const char *key, const std::string &value)
    {
        jstring jKey = e->NewStringUTF(key);
        jstring jValue = e->NewStringUTF(value.c_str());
        e->CallObjectMethod(map, put, jKey, jValue);
        e->DeleteLocalRef(jKey);
        e->DeleteLocalRef(jValue);
    };

    auto putInt = [&](const char *key, int value)
    {
        jclass intCls = e->FindClass("java/lang/Integer");
        jmethodID valueOf = e->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");
        jstring jKey = e->NewStringUTF(key);
        jobject jValue = e->CallStaticObjectMethod(intCls, valueOf, value);
        e->CallObjectMethod(map, put, jKey, jValue);
        e->DeleteLocalRef(jKey);
        e->DeleteLocalRef(jValue);
    };

    putInt("id", info.id);
    putString("magnetUri", info.magnetUri);
    putString("savePath", info.savePath);
    putString("displayName", info.displayName);
    putString("state", torrentStateToString(info.state));
    putString("lastError", info.lastError);

    // Convert timestamp to milliseconds
    auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(
                      info.createdAt.time_since_epoch())
                      .count();

    jclass longCls = e->FindClass("java/lang/Long");
    jmethodID longValueOf = e->GetStaticMethodID(longCls, "valueOf", "(J)Ljava/lang/Long;");
    jstring jKey = e->NewStringUTF("createdAt");
    jobject jValue = e->CallStaticObjectMethod(longCls, longValueOf, static_cast<jlong>(millis));
    e->CallObjectMethod(map, put, jKey, jValue);
    e->DeleteLocalRef(jKey);
    e->DeleteLocalRef(jValue);

    return map;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_getLastError(JNIEnv *e, jobject, jint id)
{
    std::string error = g_mgr->getLastError(id);
    return e->NewStringUTF(error.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_applyConfig(JNIEnv *env, jobject, jobject configMap)
{
    // Helper to get integer value from map
    auto getInt = [&](const char* key, int defaultValue) -> int {
        jclass mapClass = env->GetObjectClass(configMap);
        jmethodID getMethod = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
        jstring keyStr = env->NewStringUTF(key);
        jobject valueObj = env->CallObjectMethod(configMap, getMethod, keyStr);
        env->DeleteLocalRef(keyStr);
        
        if (valueObj != nullptr) {
            jclass intClass = env->FindClass("java/lang/Integer");
            jmethodID intValueMethod = env->GetMethodID(intClass, "intValue", "()I");
            int result = env->CallIntMethod(valueObj, intValueMethod);
            env->DeleteLocalRef(valueObj);
            return result;
        }
        return defaultValue;
    };
    
    // Helper to get boolean value from map
    auto getBool = [&](const char* key, bool defaultValue) -> bool {
        jclass mapClass = env->GetObjectClass(configMap);
        jmethodID getMethod = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
        jstring keyStr = env->NewStringUTF(key);
        jobject valueObj = env->CallObjectMethod(configMap, getMethod, keyStr);
        env->DeleteLocalRef(keyStr);
        
        if (valueObj != nullptr) {
            jclass boolClass = env->FindClass("java/lang/Boolean");
            jmethodID boolValueMethod = env->GetMethodID(boolClass, "booleanValue", "()Z");
            bool result = env->CallBooleanMethod(valueObj, boolValueMethod);
            env->DeleteLocalRef(valueObj);
            return result;
        }
        return defaultValue;
    };
    
    // Helper to get string value from map
    auto getString = [&](const char* key, const std::string& defaultValue) -> std::string {
        jclass mapClass = env->GetObjectClass(configMap);
        jmethodID getMethod = env->GetMethodID(mapClass, "get", "(Ljava/lang/Object;)Ljava/lang/Object;");
        jstring keyStr = env->NewStringUTF(key);
        jobject valueObj = env->CallObjectMethod(configMap, getMethod, keyStr);
        env->DeleteLocalRef(keyStr);
        
        if (valueObj != nullptr) {
            jstring strValue = static_cast<jstring>(valueObj);
            const char* cStr = env->GetStringUTFChars(strValue, nullptr);
            std::string result(cStr);
            env->ReleaseStringUTFChars(strValue, cStr);
            env->DeleteLocalRef(valueObj);
            return result;
        }
        return defaultValue;
    };

    // Extract configuration values
    tc::ManagerConfig newConfig;
    newConfig.maxTorrents = getInt("maxTorrents", 20);
    newConfig.maxDownloadRate = getInt("maxDownloadRate", 0);
    newConfig.maxUploadRate = getInt("maxUploadRate", 0);
    newConfig.enableDHT = getBool("enableDHT", true);
    newConfig.userAgent = getString("userAgent", "simple_torrent/1.0");
    
    // Apply the configuration
    if (g_mgr) {
        g_mgr->applyConfig(newConfig);
    }
}
