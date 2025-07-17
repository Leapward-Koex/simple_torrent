// torrent_core.hpp  ────────────────────────────────────────────────
#pragma once
#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <functional>
#include <mutex>
#include <unordered_map>
#include <libtorrent/torrent_info.hpp>
#include <thread>
#include <atomic>
#include <chrono>
#include <vector>

namespace tc
{
    enum class TorrentState
    {
        Starting,
        DownloadingMetadata,
        Downloading,
        Seeding,
        Paused,
        Error,
        Stopped
    };

    struct ManagerConfig
    {
        int maxTorrents = 20;
        int statsUpdateIntervalMs = 500;
        int maxDownloadRate = 0; // 0 = unlimited (KB/s)
        int maxUploadRate = 0;   // 0 = unlimited (KB/s)
        bool enableDHT = true;
        std::string userAgent = "simple_torrent/1.0";
    };

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
        std::string phase;
        TorrentState state = TorrentState::Starting;
    };

    struct Metadata
    {
        int id = 0;
        std::string name;            // display name
        std::int64_t totalBytes = 0; // overall payload size
        int pieceSize = 0;           // bytes per piece
        int pieceCount = 0;
        int fileCount = 0;
        std::time_t creationDate = 0; // 0 if field absent
        bool isPrivate = false;
        bool isV2 = false;
    };

    struct TorrentInfo
    {
        int id = 0;
        std::string magnetUri;
        std::string savePath;
        std::string displayName;
        TorrentState state = TorrentState::Starting;
        std::string lastError;
        std::chrono::system_clock::time_point createdAt;
    };

    using StatsCb = std::function<void(const Stats &)>;
    using MetadataCb = std::function<void(const Metadata &)>;

    class Manager
    {
    public:
        explicit Manager(const ManagerConfig &config = {});
        ~Manager();

        // returns 0 on failure
        int start(const std::string &magnet, const std::string &path,
                  StatsCb cb, MetadataCb metaCb, const std::string &displayName = "");
        void pause(int id);
        void resume(int id);
        void cancel(int id);
        void finalise(int id);

        // New management API
        std::vector<int> getActiveTorrentIds() const;
        bool exists(int id) const;
        TorrentState getState(int id) const;
        TorrentInfo getTorrentInfo(int id) const;
        std::string getLastError(int id) const;

        // Configuration update
        void applyConfig(const ManagerConfig &newConfig);

    private:
        struct Entry
        {
            libtorrent::torrent_handle torrentHandle;
            StatsCb statsCallback;
            MetadataCb metaCallback;
            std::string magnetUri;
            std::string savePath;
            std::string displayName;
            TorrentState state = TorrentState::Starting;
            std::string lastError;
            std::chrono::system_clock::time_point createdAt;
            std::atomic<bool> metadataDelivered{false};
            mutable std::chrono::steady_clock::time_point lastStatsUpdate;
            mutable libtorrent::torrent_status cachedStatus;
            mutable std::mutex callbackMutex;
            bool manuallyPaused = false; // Track user-initiated pauses

            // Make Entry movable but not copyable
            Entry() = default;
            Entry(const Entry &) = delete;
            Entry &operator=(const Entry &) = delete;
            Entry(Entry &&) = default;
            Entry &operator=(Entry &&) = default;
        };

        // Improved polling system
        void pollAll();
        void processAlerts();
        void updateAllStats();
        void updateTorrentStats(int id, Entry &entry);
        libtorrent::torrent_status getStatus(Entry &entry);
        void handleMetadataAlert(libtorrent::metadata_received_alert *alert);
        void handleMetadataFailedAlert(libtorrent::metadata_failed_alert *alert);
        void handleErrorAlert(libtorrent::torrent_error_alert *alert);
        TorrentState stateFromLibtorrentState(libtorrent::torrent_status::state_t state) const;
        std::string phaseFromState(libtorrent::torrent_status::state_t state) const;

        // Single background thread
        std::thread pollThread_;
        std::atomic<bool> shouldStop_{false};
        static constexpr auto STATS_UPDATE_INTERVAL = std::chrono::milliseconds(500);

        std::unique_ptr<libtorrent::session> ses_;
        mutable std::mutex mtx_;
        std::unordered_map<int, Entry> map_;
        int nextId_ = 1;
        ManagerConfig config_;
    };

} // namespace tc
