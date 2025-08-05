// torrent_core.cpp  ────────────────────────────────────────────────
#include "torrent_core.hpp"
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>
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
        settings_pack sp;
        sp.set_int(settings_pack::alert_mask,
                   alert::status_notification |
                       alert::error_notification |
                       alert::storage_notification);

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

        ses_ = std::make_unique<session>(sp);

        // Start single background thread for all torrents
        pollThread_ = std::thread(&Manager::pollAll, this);
    }

    Manager::~Manager()
    {
        shouldStop_ = true;
        if (pollThread_.joinable())
        {
            pollThread_.join();
        }
    }

    // ──────────────────────────────────────────── Public API ──────────
    int Manager::start(const std::string &magnet,
                       const std::string &path,
                       StatsCb cb,
                       MetadataCb metaCb,
                       const std::string &displayName)
    {
        if (magnet.empty() || path.empty() || !cb)
        {
            return 0; // Invalid parameters
        }

        std::lock_guard lock(mtx_);
        if (static_cast<int>(map_.size()) >= config_.maxTorrents)
        {
            return 0; // Too many torrents
        }

        add_torrent_params params;
        params.save_path = path;

        error_code ec;
        parse_magnet_uri(magnet, params, ec);
        if (ec)
        {
            return 0; // Bad magnet
        }

        int id = nextId_++;
        torrent_handle handle = ses_->add_torrent(params, ec);
        if (ec || !handle.is_valid())
        {
            return 0; // Failed to add
        }

        // Use emplace to construct Entry in-place
        auto [it, inserted] = map_.try_emplace(id);
        if (!inserted)
        {
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

        return id;
    }

    void Manager::pause(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            it->second.torrentHandle.pause();
            it->second.state = TorrentState::Paused;
            it->second.manuallyPaused = true; // Track manual pause
        }
    }

    void Manager::resume(int id)
    {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end())
        {
            it->second.torrentHandle.resume();
            it->second.manuallyPaused = false; // Clear manual pause flag
            it->second.state = TorrentState::Downloading;
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

            // Respect manual pause state - don't override if manually paused
            if (entry.manuallyPaused || (entry.torrentHandle.flags() & libtorrent::torrent_flags::paused))
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
                printf("State change for torrent %d: %d -> %d (libtorrent state: %d, manually paused: %s)\n",
                       id, static_cast<int>(entry.state), static_cast<int>(newState),
                       static_cast<int>(st.state), entry.manuallyPaused ? "true" : "false");
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
                stats.phase = phaseFromState(st.state);
                stats.state = entry.state; // This will now be the updated state

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
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle &&
                !entry.metadataDelivered.exchange(true))
            {

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
                }

                entry.state = TorrentState::Downloading;

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
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle &&
                !entry.metadataDelivered.exchange(true))
            {

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
        std::lock_guard lock(mtx_);

        for (auto &[id, entry] : map_)
        {
            if (entry.torrentHandle == alert->handle)
            {
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

    std::string Manager::phaseFromState(torrent_status::state_t s) const
    {
        using st = torrent_status;
        switch (s)
        {
        case st::checking_files:
        case st::checking_resume_data:
            return "checking";
        case st::downloading_metadata:
            return "downloading_metadata";
        case st::downloading:
            return "downloading";
        case st::seeding:
        case st::finished:
            return "seeding";
        default:
            return "unknown";
        }
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
