#include "torrent_core.hpp"
#include <jni.h>
#include <mutex>

static JavaVM *g_vm = nullptr;
static jclass g_cls = nullptr;
static jmethodID g_sendStats = nullptr;

static std::mutex g_mtx;
static std::unique_ptr<tc::Manager> g_mgr;

static JNIEnv *attach()
{
    JNIEnv *env = nullptr;
    g_vm->AttachCurrentThread(&env, nullptr);
    return env;
}
static void detach() { g_vm->DetachCurrentThread(); }

static void toJava(const tc::Stats &s)
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

    jobject m = env->NewObject(mapCls, ctor);
#define PUT(k, v)                              \
    {                                          \
        jstring _k = env->NewStringUTF(k);     \
        jobject _v = jintObj(v);               \
        env->CallObjectMethod(m, put, _k, _v); \
        env->DeleteLocalRef(_k);               \
        env->DeleteLocalRef(_v);               \
    }

    PUT("id", s.id)
    PUT("download_rate", s.dlRate)
    PUT("upload_rate", s.ulRate)
    PUT("pieces", s.pieces)
    PUT("pieces_total", s.piecesTotal)
        PUT("progress", s.progressPct) PUT("seeds", s.seeds) PUT("peers", s.peers)
#undef PUT

            env->CallStaticVoidMethod(g_cls, g_sendStats, m);
    env->DeleteLocalRef(m);
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
    return g_mgr->start(jstr(e, jMag), jstr(e, jPath), toJava);
}
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_pauseTorrent(JNIEnv *, jobject, jint id) { g_mgr->pause(id); }
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_resumeTorrent(JNIEnv *, jobject, jint id) { g_mgr->resume(id); }
extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_cancelTorrent(JNIEnv *, jobject, jint id) { g_mgr->cancel(id); }
