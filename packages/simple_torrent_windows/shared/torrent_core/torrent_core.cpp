// torrent_core.cpp  ────────────────────────────────────────────────
#include "torrent_core.hpp"
#include "torrent_state_helpers.hpp"
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/hex.hpp>
#include <thread>
#include <chrono>
#include <algorithm>
#include <cstdio>

namespace tc
{
    using namespace libtorrent;

    // ───────────────────────────────── Manager ctor / dtor ────────────
    Manager::Manager(const ManagerConfig &config) : config_(config)
    {
        printf("[TorrentCore] Initializing session with config:\n");
        printf("  - DHT enabled: %s\n", config_.enableDHT ? "true" : "false");
        printf("  - Max download rate: %d KB/s\n", config_.maxDownloadRate);
        printf("  - Max upload rate: %d KB/s\n", config_.maxUploadRate);
        printf("  - User agent: %s\n", config_.userAgent.c_str());

        settings_pack sp;
        sp.set_int(settings_pack::alert_mask,
                   alert::status_notification |
                       alert::error_notification |
                       alert::storage_notification |
                       alert::tracker_notification |
                       alert::peer_notification |
                       alert::dht_notification);

        if (config_.maxDownloadRate > 0)
        {
            sp.set_int(settings_pack::download_rate_limit, config_.maxDownloadRate * 1024);
        }
        if (config_.maxUploadRate > 0)
        {
            sp.set_int(settings_pack::upload_rate_limit, config_.maxUploadRate * 1024);
        }

        sp.set_bool(settings_pack::enable_dht, config_.enableDHT);
        sp.set_str(settings_pack::user_agent, config_.userAgent);

        // Add more network settings for better connectivity
        sp.set_bool(settings_pack::enable_lsd, true);  // Local Service Discovery
        sp.set_bool(settings_pack::enable_upnp, true); // UPnP port mapping
        sp.set_bool(settings_pack::enable_natpmp, true); // NAT-PMP port mapping
        sp.set_int(settings_pack::connections_limit, 200);
        
        // DHT settings
        if (config_.enableDHT) {
            sp.set_int(settings_pack::dht_announce_interval, 15 * 60); // 15 minutes
            sp.set_str(settings_pack::dht_bootstrap_nodes, 
                      "router.bittorrent.com:6881,"
                      "dht.transmissionbt.com:6881,"
                      "router.utorrent.com:6881");
        }

        printf("[TorrentCore] Creating libtorrent session...\n");
        ses_ = std::make_unique<session>(sp);
        printf("[TorrentCore] Session created successfully\n");

        // Start single background thread for all torrents
        pollThread_ = std::thread(&Manager::pollAll, this);
        printf("[TorrentCore] Background polling thread started\n");
    }

    Manager::~Manager()
    {
        printf("[TorrentCore] Shutting down manager...\n");
        shouldStop_ = true;
        if (pollThread_.joinable())
        {
            pollThread_.join();
        }
        printf("[TorrentCore] Manager shutdown complete\n");
    }

    // ──────────────────────────────────────────── Public API ──────────
    int Manager::start(const std::string &magnet,
                       const std::string &path,
                       StatsCb cb,
                       MetadataCb metaCb,
                       const std::string &displayName)
    {
        printf("[TorrentCore] Starting torrent:\n");
        printf("  - Magnet: %s\n", magnet.c_str());
        printf("  - Save path: %s\n", path.c_str());
        printf("  - Display name: %s\n", displayName.c_str());
        
        if (magnet.empty() || path.empty() || !cb)
        {
            printf("[TorrentCore] ERROR: Invalid parameters\n");
            return 0; // Invalid parameters
        }

        std::lock_guard lock(mtx_);
        if (static_cast<int>(map_.size()) >= config_.maxTorrents)
        {
            printf("[TorrentCore] ERROR: Too many torrents (%d >= %d)\n", 
                   static_cast<int>(map_.size()), config_.maxTorrents);
            return 0; // Too many torrents
        }

        add_torrent_params params;
        params.save_path = path;

        error_code ec;
        parse_magnet_uri(magnet, params, ec);
        if (ec)
        {
            printf("[TorrentCore] ERROR: Failed to parse magnet URI: %s\n", ec.message().c_str());
            return 0; // Bad magnet
        }

        printf("[TorrentCore] Magnet URI parsed successfully\n");
        printf("  - Info hash: %s\n", params.info_hashes.has_v1() ? 
               libtorrent::aux::to_hex(params.info_hashes.v1).c_str() : "none");
        printf("  - Tracker count: %zu\n", params.trackers.size());
        for (size_t i = 0; i < params.trackers.size() && i < 5; ++i) {
            printf("    [%zu] %s\n", i, params.trackers[i].c_str());
        }

        int id = nextId_++;
        printf("[TorrentCore] Adding torrent to session with ID %d\n", id);
        
        torrent_handle handle = ses_->add_torrent(params, ec);
        if (ec || !handle.is_valid())
        {
            printf("[TorrentCore] ERROR: Failed to add torrent to session: %s\n", 
                   ec.message().c_str());
            return 0; // Failed to add
        }

        printf("[TorrentCore] Torrent added to session successfully\n");

        // Use emplace to construct Entry in-place
        auto [it, inserted] = map_.try_emplace(id);
        if (!inserted)
        {
            printf("[TorrentCore] ERROR: ID collision for torrent %d\n", id);
            return 0; // ID collision (shouldn't happen)
        }

        Entry &entry = it->second;
        entry.torrentHandle = std::move(handle);
        entry.statsCallback = std::move(cb);
        entry.metaCallback = std::move(metaCb);
        entry.magnetUri = magnet;
        entry.savePath = path;
        entry.displayName = displayName.empty() ? "Torrent " + std::to_string(id) : displayName;
        entry.state = TorrentState::Starting;
        entry.createdAt = std::chrono::system_clock::now();
        entry.lastStatsUpdate = std::chrono::steady_clock::now();

        printf("[TorrentCore] Torrent %d setup complete, starting download\n", id);
        return id;
    }

    int Manager::startFromTorrentData(const std::vector<char> &torrentData,
                                      const std::string &path,
                                      StatsCb cb,
                                      MetadataCb metaCb,
                                      const std::string &displayName)
    {
        if (torrentData.empty() || path.empty() || !cb) {
            return 0; // Invalid parameters
        }

        // Parse the in‑memory buffer FIRST (may throw) – do this outside the lock.
        libtorrent::add_torrent_params params;
        try {
            params = libtorrent::load_torrent_buffer(
                    libtorrent::span<char const>(torrentData.data(), torrentData.size()));
        } catch (std::exception const &) {
            return 0; // Not a valid .torrent buffer
        }

        params.save_path = path;

        // ───────────────────────────── Session insertion ────────────────────────────
        std::lock_guard lock(mtx_);
        if (static_cast<int>(map_.size()) >= config_.maxTorrents) {
            return 0; // Over torrent limit
        }

        int id = nextId_++;
        libtorrent::error_code ec;
        libtorrent::torrent_handle handle = ses_->add_torrent(params, ec);
        if (ec || !handle.is_valid()) {
            return 0; // Failed to add
        }

        auto [it, inserted] = map_.try_emplace(id);
        if (!inserted) {
            return 0;
        }

        Entry &entry = it->second;
        entry.torrentHandle = std::move(handle);
        entry.statsCallback = std::move(cb);
        entry.metaCallback = std::move(metaCb);
        entry.magnetUri.clear(); // Not applicable
        entry.savePath = path;
        entry.displayName = displayName.empty() && params.ti ? params.ti->name() : displayName;
        entry.state = TorrentState::Starting;
        entry.createdAt = std::chrono::system_clock::now();
        entry.lastStatsUpdate = std::chrono::steady_clock::now();

        // Deliver metadata immediately because we already possess the full .torrent.
        if (entry.metaCallback && params.ti && !entry.metadataDelivered.exchange(true)) {
            Metadata m;
            m.id = id;
            m.name = params.ti->name();
            m.totalBytes = params.ti->total_size();
            m.pieceSize = params.ti->piece_length();
            m.pieceCount = params.ti->num_pieces();
            m.fileCount = params.ti->num_files();
            m.creationDate = params.ti->creation_date();
            m.isPrivate = params.ti->priv();
            m.isV2 = params.ti->v2();

            std::lock_guard cbLock(entry.callbackMutex);
            entry.metaCallback(m);
        }

        return id;
    }

    int Manager::startFromTorrentFile(const std::string &torrentFilepath,
                                      const std::string &path,
                                      StatsCb cb,
                                      MetadataCb metaCb,
                                      const std::string &displayName)
    {
        if (torrentFilepath.empty() || path.empty() || !cb) {
            return 0; // Invalid parameters
        }

        // Let libtorrent read and parse the .torrent straight from disk.
        libtorrent::add_torrent_params params;
        try {
            params = libtorrent::load_torrent_file(torrentFilepath);
        } catch (std::exception const &) {
            return 0; // Could not parse file
        }

        params.save_path = path;

        // ───────────────────────────── Session insertion ────────────────────────────
        std::lock_guard lock(mtx_);
        if (static_cast<int>(map_.size()) >= config_.maxTorrents) {
            return 0;
        }

        int id = nextId_++;
        libtorrent::error_code ec;
        libtorrent::torrent_handle handle = ses_->add_torrent(params, ec);
        if (ec || !handle.is_valid()) {
            return 0;
        }

        auto [it, inserted] = map_.try_emplace(id);
        if (!inserted) {
            return 0;
        }

        Entry &entry = it->second;
        entry.torrentHandle = std::move(handle);
        entry.statsCallback = std::move(cb);
        entry.metaCallback = std::move(metaCb);
        entry.magnetUri.clear();
        entry.savePath = path;
        entry.displayName = displayName.empty() && params.ti ? params.ti->name() : displayName;
        entry.state = TorrentState::Starting;
        entry.createdAt = std::chrono::system_clock::now();
        entry.lastStatsUpdate = std::chrono::steady_clock::now();

        if (entry.metaCallback && params.ti && !entry.metadataDelivered.exchange(true)) {
            Metadata m;
            m.id = id;
            m.name = params.ti->name();
            m.totalBytes = params.ti->total_size();
            m.pieceSize = params.ti->piece_length();
            m.pieceCount = params.ti->num_pieces();
            m.fileCount = params.ti->num_files();
            m.creationDate = params.ti->creation_date();
            m.isPrivate = params.ti->priv();
            m.isV2 = params.ti->v2();

            std::lock_guard cbLock(entry.callbackMutex);
            entry.metaCallback(m);
        }

        return id;
    }


    void Manager::pause(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            // Unset auto_managed so the torrent stays paused indefinitely
            it->second.torrentHandle.unset_flags(libtorrent::torrent_flags::auto_managed);
            it->second.torrentHandle.pause(); // state will update automatically
        }
    }

    void Manager::resume(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            // Restore auto_managed so libtorrent can manage the torrent again
            it->second.torrentHandle.set_flags(libtorrent::torrent_flags::auto_managed);
            it->second.torrentHandle.resume();
        }
    }

    void Manager::cancel(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            // User‑initiated cancel: delete files.
            ses_->remove_torrent(it->second.torrentHandle, session::delete_files);
            map_.erase(it);
        }
    }

    // Remove torrent from the session WITHOUT deleting payload data — used when
    // we reach finished/seeding state so the files stay on disk for the next
    // app launch.
    void Manager::finalise(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            ses_->remove_torrent(it->second.torrentHandle); // keep files
            map_.erase(it);
        }
    }

    // New management API
    std::vector<int> Manager::getActiveTorrentIds() const
    {
        std::lock_guard lock(mtx_);
        std::vector<int> ids;
        ids.reserve(map_.size());
        for (const auto &[id, _] : map_)
        {
            ids.push_back(id);
        }
        return ids;
    }

    bool Manager::exists(int id) const
    {
        std::lock_guard lock(mtx_);
        return map_.find(id) != map_.end();
    }

    TorrentState Manager::getState(int id) const
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            return it->second.state;
        }
        return TorrentState::Error;
    }

    TorrentInfo Manager::getTorrentInfo(int id) const
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            const Entry &entry = it->second;
            TorrentInfo info;
            info.id = id;
            info.magnetUri = entry.magnetUri;
            info.savePath = entry.savePath;
            info.displayName = entry.displayName;
            info.state = entry.state;
            info.lastError = entry.lastError;
            info.createdAt = entry.createdAt;
            return info;
        }
        return {};
    }

    std::string Manager::getLastError(int id) const
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            return it->second.lastError;
        }
        return "Torrent not found";
    }

    // ─────────────────────────────── Improved polling system ──────────
    void Manager::pollAll()
    {
        while (!shouldStop_)
        {
            processAlerts();
            updateAllStats();
            std::this_thread::sleep_for(std::chrono::milliseconds(config_.statsUpdateIntervalMs));
        }
    }

    void Manager::processAlerts()
    {
        std::vector<alert *> alerts;
        ses_->pop_alerts(&alerts);

        for (alert *a : alerts)
        {
            // Log all alerts for debugging
            printf("[TorrentCore] Alert: %s - %s\n", a->what(), a->message().c_str());
            
            if (auto *md = alert_cast<metadata_received_alert>(a))
            {
                handleMetadataAlert(md);
            }
            else if (auto *mf = alert_cast<metadata_failed_alert>(a))
            {
                handleMetadataFailedAlert(mf);
            }
            else if (auto *err = alert_cast<torrent_error_alert>(a))
            {
                handleErrorAlert(err);
            }
            // Add more specific alert handling for debugging peer connections
            else if (auto *peer_connect = alert_cast<peer_connect_alert>(a))
            {
                printf("[TorrentCore] Peer connected: %s\n", 
                       peer_connect->endpoint.address().to_string().c_str());
            }
            else if (auto *peer_disconnect = alert_cast<peer_disconnected_alert>(a))
            {
                printf("[TorrentCore] Peer disconnected: %s (reason: %s)\n", 
                       peer_disconnect->endpoint.address().to_string().c_str(),
                       peer_disconnect->message().c_str());
            }
            else if (auto *tracker_announce = alert_cast<tracker_announce_alert>(a))
            {
                printf("[TorrentCore] Announcing to tracker\n");
            }
            else if (auto *tracker_reply = alert_cast<tracker_reply_alert>(a))
            {
                printf("[TorrentCore] Tracker reply - %d peers\n", tracker_reply->num_peers);
            }
            else if (auto *tracker_error = alert_cast<tracker_error_alert>(a))
            {
                printf("[TorrentCore] Tracker error: %s\n", tracker_error->message().c_str());
            }
            else if (auto *dht_announce = alert_cast<dht_announce_alert>(a))
            {
                printf("[TorrentCore] DHT announce\n");
            }
            else if (auto *dht_get_peers = alert_cast<dht_get_peers_alert>(a))
            {
                printf("[TorrentCore] DHT get_peers\n");
            }
        }
    }

    void Manager::updateAllStats()
    {
        std::vector<std::pair<int, Entry *>> snapshot;

        // Quick snapshot with minimal lock time
        {
            std::lock_guard lock(mtx_);
            snapshot.reserve(map_.size());
            for (auto &[id, entry] : map_)
            {
                if (entry.torrentHandle.is_valid())
                {
                    snapshot.emplace_back(id, &entry);
                }
            }
        }

        // Process without holding main lock
        for (auto &[id, entry] : snapshot)
        {
            updateTorrentStats(id, *entry);
        }
    }

    void Manager::updateTorrentStats(int id, Entry &entry)
    {
        try
        {
            torrent_status st = getStatus(entry);

            // Update state FIRST, before sending stats
            TorrentState newState = stateFromLibtorrentState(st.state);

            // Reflect libtorrent's paused flag
            if (entry.torrentHandle.flags() & libtorrent::torrent_flags::paused)
            {
                newState = TorrentState::Paused;
            }

            // Debug: Log state changes
            if (entry.state != newState)
            {
                // Force a fresh status update on state change
                entry.cachedStatus = entry.torrentHandle.status();
                entry.lastStatsUpdate = std::chrono::steady_clock::now();
                st = entry.cachedStatus;

                // Log the state change for debugging
                printf("State change for torrent %d: %d -> %d (libtorrent state: %d)\n",
                       id, static_cast<int>(entry.state), static_cast<int>(newState),
                       static_cast<int>(st.state));
            }

            // UPDATE: Apply state change BEFORE sending stats
            entry.state = newState;

            // Only send stats if there's a callback
            if (entry.statsCallback)
            {
                Stats stats;
                stats.id = id;
                stats.dlRate = st.download_payload_rate;
                stats.ulRate = st.upload_payload_rate;
                stats.pieces = st.num_pieces;
                stats.piecesTotal = entry.torrentHandle.torrent_file() ? entry.torrentHandle.torrent_file()->num_pieces() : 0;
                stats.progress = st.progress;
                stats.seeds = st.num_seeds;
                stats.peers = st.num_peers;
                stats.state = entry.state; // This will now be the updated state

                // Add detailed debugging for peer connectivity issues
                static int logCounter = 0;
                if (logCounter++ % 20 == 0) { // Log every 10 seconds (500ms * 20)
                    printf("[TorrentCore] Torrent %d stats:\n", id);
                    printf("  - State: %s\n", stateToString(stats.state));
                    printf("  - Progress: %.1f%%\n", stats.progress * 100.0f);
                    printf("  - Download rate: %d B/s\n", stats.dlRate);
                    printf("  - Upload rate: %d B/s\n", stats.ulRate);
                    printf("  - Seeds: %d (connected: %d)\n", stats.seeds, st.num_seeds);
                    printf("  - Peers: %d (connected: %d)\n", stats.peers, st.num_peers);
                    printf("  - List seeds: %d, List peers: %d\n", st.list_seeds, st.list_peers);
                    printf("  - Connect candidates: %d\n", st.connect_candidates);
                    printf("  - Total download: %lld bytes\n", st.total_download);
                    printf("  - Total upload: %lld bytes\n", st.total_upload);
                    printf("  - All time download: %lld bytes\n", st.all_time_download);
                    printf("  - All time upload: %lld bytes\n", st.all_time_upload);
                    printf("  - Has metadata: %s\n", st.has_metadata ? "yes" : "no");
                    
                    printf("---\n");
                }

                // Thread-safe callback execution
                {
                    std::lock_guard callbackLock(entry.callbackMutex);
                    entry.statsCallback(stats);
                }
            }
        }
        catch (const std::exception &e)
        {
            entry.lastError = e.what();
            entry.state = TorrentState::Error;
        }
    }

    torrent_status Manager::getStatus(Entry &entry)
    {
        auto now = std::chrono::steady_clock::now();
        if (now - entry.lastStatsUpdate > STATS_UPDATE_INTERVAL)
        {
            entry.cachedStatus = entry.torrentHandle.status();
            entry.lastStatsUpdate = now;
        }
        return entry.cachedStatus;
    }

    void Manager::handleMetadataAlert(metadata_received_alert *alert)
    {
        printf("[TorrentCore] Metadata received for torrent\n");
        
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle &&
                !entry.metadataDelivered.exchange(true))
            {
                printf("[TorrentCore] Processing metadata for torrent %d\n", id);

                Metadata m;
                m.id = id;
                if (auto info = alert->handle.torrent_file())
                {
                    m.name = info->name();
                    m.totalBytes = info->total_size();
                    m.pieceSize = info->piece_length();
                    m.pieceCount = info->num_pieces();
                    m.fileCount = info->num_files();
                    m.creationDate = info->creation_date();
                    m.isPrivate = info->priv();
                    m.isV2 = info->v2();
                    
                    printf("[TorrentCore] Metadata details:\n");
                    printf("  - Name: %s\n", m.name.c_str());
                    printf("  - Size: %lld bytes\n", m.totalBytes);
                    printf("  - Pieces: %d (each %d bytes)\n", m.pieceCount, m.pieceSize);
                    printf("  - Files: %d\n", m.fileCount);
                    printf("  - Private: %s\n", m.isPrivate ? "yes" : "no");
                }

                entry.state = TorrentState::Downloading;
                printf("[TorrentCore] Torrent %d state changed to Downloading\n", id);

                // Thread-safe callback execution
                {
                    std::lock_guard callbackLock(entry.callbackMutex);
                    if (entry.metaCallback)
                    {
                        entry.metaCallback(m);
                    }
                }
                break;
            }
        }
    }

    void Manager::handleMetadataFailedAlert(metadata_failed_alert *alert)
    {
        printf("[TorrentCore] Metadata failed for torrent: %s\n", alert->message().c_str());
        
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle &&
                !entry.metadataDelivered.exchange(true))
            {
                printf("[TorrentCore] Metadata failed for torrent %d: %s\n", id, alert->message().c_str());
                entry.state = TorrentState::Error;
                entry.lastError = "Failed to download metadata";

                // Send empty metadata as failure marker
                Metadata m;
                m.id = id;

                {
                    std::lock_guard callbackLock(entry.callbackMutex);
                    if (entry.metaCallback)
                    {
                        entry.metaCallback(m);
                    }
                }
                break;
            }
        }
    }

    void Manager::handleErrorAlert(torrent_error_alert *alert)
    {
        printf("[TorrentCore] Torrent error: %s\n", alert->error.message().c_str());
        
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle)
            {
                printf("[TorrentCore] Error for torrent %d: %s\n", id, alert->error.message().c_str());
                entry.state = TorrentState::Error;
                entry.lastError = alert->error.message();
                break;
            }
        }
    }

    TorrentState Manager::stateFromLibtorrentState(torrent_status::state_t state) const
    {
        using st = torrent_status;
        switch (state)
        {
        case st::checking_files:
        case st::checking_resume_data:
            return TorrentState::Starting;
        case st::downloading_metadata:
            return TorrentState::DownloadingMetadata;
        case st::downloading:
            return TorrentState::Downloading;
        case st::seeding:
        case st::finished:
            return TorrentState::Seeding;
        default:
            return TorrentState::Error;
        }
    }

    const char* Manager::stateToString(TorrentState state) const
    {
        return tc::stateToString(state);
    }


    void Manager::applyConfig(const ManagerConfig &newConfig)
    {
        std::lock_guard lock(mtx_);

        // Update our config
        config_ = newConfig;

        // Apply session settings
        settings_pack sp;

        if (config_.maxDownloadRate > 0)
        {
            sp.set_int(settings_pack::download_rate_limit, config_.maxDownloadRate * 1024);
        }
        else
        {
            sp.set_int(settings_pack::download_rate_limit, 0); // Unlimited
        }

        if (config_.maxUploadRate > 0)
        {
            sp.set_int(settings_pack::upload_rate_limit, config_.maxUploadRate * 1024);
        }
        else
        {
            sp.set_int(settings_pack::upload_rate_limit, 0); // Unlimited
        }

        sp.set_bool(settings_pack::enable_dht, config_.enableDHT);
        sp.set_str(settings_pack::user_agent, config_.userAgent);

        // Apply the new settings to the running session
        ses_->apply_settings(sp);
    }
} // namespace tc
