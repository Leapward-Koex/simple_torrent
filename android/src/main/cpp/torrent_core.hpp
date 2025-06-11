// torrent_core.hpp  ────────────────────────────────────────────────
#pragma once
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <functional>
#include <mutex>
#include <unordered_map>
#include <libtorrent/torrent_info.hpp>

namespace tc
{

    struct Stats
    {
        int id = 0;
        int dlRate = 0;
        int ulRate = 0;
        int pieces = 0;
        int piecesTotal = 0;
        int progressPct = 0;
        int seeds = 0;
        int peers = 0;
    };

    struct Metadata
    {
        int                 id            = 0;
        std::string         name;                 // display name
        std::int64_t        totalBytes    = 0;    // overall payload size
        int                 pieceSize     = 0;    // bytes per piece
        int                 pieceCount    = 0;
        int                 fileCount     = 0;
        std::time_t         creationDate  = 0;    // 0 if field absent
        bool                isPrivate     = false;
        bool                isV2          = false;
    };

    using StatsCb = std::function<void(const Stats &)>;
    using MetadataCb = std::function<void(const Metadata &)>;

    class Manager
    {
    public:
        explicit Manager(int maxTorrents = 20);
        ~Manager();

        // returns 0 on failure
        int start(const std::string &magnet, const std::string &path,
                  StatsCb cb, MetadataCb metaCb);
        void pause(int id);
        void resume(int id);
        void cancel(int id);

    private:
        struct Entry
        {
            libtorrent::torrent_handle torrentHandle;
            StatsCb statsCallback;
            MetadataCb metaCallback;
        };

        void poll(int id);

        std::unique_ptr<libtorrent::session> ses_;
        std::unordered_map<int, Entry> map_;
        std::mutex mtx_;
        int nextId_ = 1;
        const int max_;
    };

} // namespace tc
