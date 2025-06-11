#include "torrent_core.hpp"
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

static void statsToJava(const tc::Stats &s)
{
    JNIEnv *env = attach();

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID ctor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapCls, "put",
                                     "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID val = env->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");

    auto jintObj = [&](int v)
    { return env->CallStaticObjectMethod(intCls, val, v); };

    jobject map = env->NewObject(mapCls, ctor);
#define PUT_STR(key, str)                             \
    {                                                 \
        jstring _k = env->NewStringUTF(key);          \
        jstring _v = env->NewStringUTF(str.c_str());  \
        env->CallObjectMethod(map, put, _k, _v);      \
        env->DeleteLocalRef(_k);                      \
        env->DeleteLocalRef(_v);                      \
    }

#define PUT(k, v)                              \
    {                                          \
        jstring _k = env->NewStringUTF(k);     \
        jobject _v = jintObj(v);               \
        env->CallObjectMethod(map, put, _k, _v); \
        env->DeleteLocalRef(_k);               \
        env->DeleteLocalRef(_v);               \
    }

    PUT_STR("eventType", std::string("metadata"));
    PUT("id", s.id)
    PUT("download_rate", s.dlRate)
    PUT("upload_rate", s.ulRate)
    PUT("pieces", s.pieces)
    PUT("pieces_total", s.piecesTotal)
    PUT("progress", s.progressPct)
    PUT("seeds", s.seeds)
    PUT("peers", s.peers)
#undef PUT
#undef PUT_STR

    env->CallStaticVoidMethod(g_cls, g_sendStats, map);
    env->DeleteLocalRef(map);
    detach();
}

static void metadataToJava(const tc::Metadata &metadata)
{
    JNIEnv *env = attach();

    jclass mapCls    = env->FindClass("java/util/HashMap");
    jmethodID ctor   = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put    = env->GetMethodID(mapCls, "put",
                                        "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jclass intCls    = env->FindClass("java/lang/Integer");
    jmethodID intVal = env->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");

    jclass longCls   = env->FindClass("java/lang/Long");
    jmethodID longVal= env->GetStaticMethodID(longCls, "valueOf", "(J)Ljava/lang/Long;");

    jclass boolCls   = env->FindClass("java/lang/Boolean");
    jmethodID boolVal= env->GetStaticMethodID(boolCls, "valueOf", "(Z)Ljava/lang/Boolean;");

    auto jintObj  = [&](int    v) { return env->CallStaticObjectMethod(intCls,  intVal,  v); };
    auto jlongObj = [&](jlong  v) { return env->CallStaticObjectMethod(longCls, longVal, v); };
    auto jboolObj = [&](bool   v) { return env->CallStaticObjectMethod(boolCls, boolVal,
                                                                       static_cast<jboolean>(v)); };

    jobject map = env->NewObject(mapCls, ctor);

#define PUT_NUM(key, valObj)                          \
    {                                                 \
        jstring _k = env->NewStringUTF(key);          \
        env->CallObjectMethod(map, put, _k, valObj);  \
        env->DeleteLocalRef(_k);                      \
        env->DeleteLocalRef(valObj);                  \
    }

#define PUT_STR(key, str)                             \
    {                                                 \
        jstring _k = env->NewStringUTF(key);          \
        jstring _v = env->NewStringUTF(str.c_str());  \
        env->CallObjectMethod(map, put, _k, _v);      \
        env->DeleteLocalRef(_k);                      \
        env->DeleteLocalRef(_v);                      \
    }


    PUT_STR("eventType", std::string("metadata"));

    PUT_NUM("id",            jintObj(metadata.id));
    PUT_STR("name", metadata.name);
    PUT_NUM("total_bytes",   jlongObj(static_cast<jlong>(metadata.totalBytes)));
    PUT_NUM("piece_size",    jintObj(metadata.pieceSize));
    PUT_NUM("piece_count",   jintObj(metadata.pieceCount));
    PUT_NUM("file_count",    jintObj(metadata.fileCount));
    PUT_NUM("creation_date", jlongObj(static_cast<jlong>(metadata.creationDate)));
    PUT_NUM("private",       jboolObj(metadata.isPrivate));
    PUT_NUM("v2",            jboolObj(metadata.isV2));

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
    g_sendMetadata  = e->GetStaticMethodID(g_cls, "sendMetadata",  "(Ljava/util/Map;)V");
    g_mgr = std::make_unique<tc::Manager>();
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
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_pauseTorrent(JNIEnv *, jobject, jint id) { g_mgr->pause(id); }
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_resumeTorrent(JNIEnv *, jobject, jint id) { g_mgr->resume(id); }
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_cancelTorrent(JNIEnv *, jobject, jint id) { g_mgr->cancel(id); }
