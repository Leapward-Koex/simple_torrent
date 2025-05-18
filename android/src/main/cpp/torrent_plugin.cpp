#include "libtorrent/session.hpp"
#include "libtorrent/magnet_uri.hpp"
#include "libtorrent/alert_types.hpp"

#include <jni.h>
#include <string>
#include <thread>
#include <chrono>
#include <unordered_map>
#include <mutex>
#include <atomic>

namespace lt = libtorrent;

class ScopedJniThread
{
public:
    explicit ScopedJniThread(JavaVM *vm) : jvm_(vm)
    {
        jvm_->AttachCurrentThread(&env_, nullptr);
    }
    ~ScopedJniThread()
    {
        if (env_)
            jvm_->DetachCurrentThread();
    }
    JNIEnv *env() const { return env_; }

private:
    JavaVM *jvm_{nullptr};
    JNIEnv *env_{nullptr};
};

static std::string to_utf8(JNIEnv *env, jstring js)
{
    const char *utf = env->GetStringUTFChars(js, nullptr);
    std::string out(utf);
    env->ReleaseStringUTFChars(js, utf);
    return out;
}

static JavaVM *g_vm = nullptr;
static jclass g_plugin_cls = nullptr;
static jmethodID g_sendStats_mid = nullptr;

static std::mutex g_mutex;
static std::unordered_map<int, lt::torrent_handle> g_handles;
static std::atomic<int> g_next_id{1};
static lt::session *g_session = nullptr;
static const int MAX_TORRENTS = 20;

static void init_session()
{
    if (!g_session)
    {
        lt::settings_pack cfg;
        cfg.set_int(lt::settings_pack::alert_mask, lt::alert::status_notification);
        g_session = new lt::session(cfg);
    }
}

extern "C" jint JNI_OnLoad(JavaVM *vm, void *)
{
    g_vm = vm;
    JNIEnv *env = nullptr;
    vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6);
    jclass local = env->FindClass("com/leapwardkoex/simple_torrent/simple_torrent/SimpleTorrentPlugin");
    g_plugin_cls = static_cast<jclass>(env->NewGlobalRef(local));
    g_sendStats_mid = env->GetStaticMethodID(g_plugin_cls, "sendStats", "(Ljava/util/Map;)V");
    env->DeleteLocalRef(local);
    init_session();
    return JNI_VERSION_1_6;
}

static void push_stats(int id, const lt::torrent_status &st, const lt::torrent_handle &torrentHandle)
{
    ScopedJniThread attach(g_vm);
    JNIEnv *env = attach.env();
    if (!env)
        return;

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID ctor = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapCls, "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jclass intCls = env->FindClass("java/lang/Integer");
    jmethodID valOf = env->GetStaticMethodID(intCls, "valueOf", "(I)Ljava/lang/Integer;");

    jobject mapObj = env->NewObject(mapCls, ctor);
    auto putInt = [&](const char *k, int v)
    {
        jstring key = env->NewStringUTF(k);
        jobject val = env->CallStaticObjectMethod(intCls, valOf, v);
        env->CallObjectMethod(mapObj, put, key, val);
        env->DeleteLocalRef(key);
        env->DeleteLocalRef(val);
    };
    putInt("id", id);
    putInt("download_rate", st.download_payload_rate);
    putInt("upload_rate", st.upload_payload_rate);
    putInt("pieces", st.num_pieces);
    int totalPieces = 0;
    if (auto tf = torrentHandle.torrent_file())
        totalPieces = tf->num_pieces();
    putInt("pieces_total", totalPieces);
    putInt("progress", static_cast<int>(st.progress * 100.0f));
    putInt("seeds", st.num_seeds);
    putInt("peers", st.num_peers);

    env->CallStaticVoidMethod(g_plugin_cls, g_sendStats_mid, mapObj);
    env->DeleteLocalRef(mapObj);
}

static void torrent_worker(int id)
{
    while (true)
    {
        lt::torrent_handle h;
        {
            std::lock_guard<std::mutex> lk(g_mutex);
            auto it = g_handles.find(id);
            if (it == g_handles.end())
                return; // cancelled
            h = it->second;
        }
        if (!h.is_valid())
            break;
        lt::torrent_status st = h.status();
        push_stats(id, st, h);
        if (st.is_seeding)
            break;
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    std::lock_guard<std::mutex> lk(g_mutex);
    g_handles.erase(id);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_startTorrent(JNIEnv *env, jobject, jstring jMagnet, jstring jDest)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    if (static_cast<int>(g_handles.size()) >= MAX_TORRENTS)
        return 0;

    std::string magnet = to_utf8(env, jMagnet);
    std::string dest = to_utf8(env, jDest);

    lt::add_torrent_params p;
    p.save_path = dest;
    lt::error_code ec;
    lt::parse_magnet_uri(magnet, p, ec);
    if (ec)
        return 0;

    int id = g_next_id++;
    lt::torrent_handle h = g_session->add_torrent(p, ec);
    if (ec)
        return 0;
    g_handles[id] = h;

    std::thread(torrent_worker, id).detach();
    return id;
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_pauseTorrent(JNIEnv *, jobject, jint id)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto it = g_handles.find(id);
    if (it != g_handles.end())
        it->second.pause();
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_resumeTorrent(JNIEnv *, jobject, jint id)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto it = g_handles.find(id);
    if (it != g_handles.end())
        it->second.resume();
}

extern "C" JNIEXPORT void JNICALL
Java_com_leapwardkoex_simple_1torrent_simple_1torrent_SimpleTorrentPlugin_cancelTorrent(JNIEnv *, jobject, jint id)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto it = g_handles.find(id);
    if (it != g_handles.end())
    {
        it->second.pause();
        g_session->remove_torrent(it->second, lt::session::delete_files);
        g_handles.erase(it);
    }
}
