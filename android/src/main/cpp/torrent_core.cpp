// torrent_core.cpp  ────────────────────────────────────────────────
#include "torrent_core.hpp"
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/alert_types.hpp>
#include <thread>
#include <chrono>

namespace tc {
    using namespace libtorrent;

    // ───────────────────────────────── Manager ctor / dtor ────────────
    Manager::Manager(int max) : max_(max) {
        settings_pack sp;
        sp.set_int(settings_pack::alert_mask, alert::status_notification);
        ses_ = std::make_unique<session>(sp);
    }
    Manager::~Manager() = default;

    // ──────────────────────────────────────────── Public API ──────────
    int Manager::start(const std::string& magnet,
                       const std::string& path,
                       StatsCb cb,
                       MetadataCb metaCb) {
        std::lock_guard lock(mtx_);
        if ((int)map_.size() >= max_) {
            return 0; // too many torrents
        }

        add_torrent_params params;
        params.save_path = path;

        error_code ec;
        parse_magnet_uri(magnet, params, ec);
        if (ec) {
            return 0; // bad magnet
        }

        // If files already exist, libtorrent will run a re‑check. Nothing extra to do here.

        int id               = nextId_++;
        torrent_handle thand = ses_->add_torrent(params, ec);
        if (ec || !thand.is_valid()) {
            return 0; // failed to add
        }

        map_[id] = {thand, std::move(cb), std::move(metaCb)};
        std::thread(&Manager::poll, this, id).detach();
        return id;
    }

    void Manager::pause(int id) {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end()) {
            it->second.torrentHandle.pause();
        }
    }

    void Manager::resume(int id) {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end()) {
            it->second.torrentHandle.resume();
        }
    }

    void Manager::cancel(int id) {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end()) {
            // User‑initiated cancel: delete files.
            ses_->remove_torrent(it->second.torrentHandle, session::delete_files);
            map_.erase(it);
        }
    }

    // Remove torrent from the session WITHOUT deleting payload data — used when
    // we reach finished/seeding state so the files stay on disk for the next
    // app launch.
    void Manager::finalise(int id) {
        std::lock_guard lock(mtx_);
        if (auto it = map_.find(id); it != map_.end()) {
            ses_->remove_torrent(it->second.torrentHandle); // keep files
            map_.erase(it);
        }
    }

    // ─────────────────────────────── Helper: readable state ───────────
    static std::string phase_from_state(torrent_status::state_t s) {
        using st = torrent_status;
        switch (s) {
            case st::checking_files:
            case st::checking_resume_data:
                return "checking";
            case st::downloading_metadata:
            case st::downloading:
                return "downloading";
            case st::seeding:
            case st::finished:
                return "seeding";
            default:
                return "unknown";
        }
    }

    // ──────────────────────────────────────────── Poll loop ───────────
    void Manager::poll(int id) {
        bool metadataDelivered = false;

        for (;;) {
            Entry snap;
            {
                std::lock_guard lock(mtx_);
                auto it = map_.find(id);
                if (it == map_.end()) {
                    return; // torrent no longer tracked
                }
                snap = it->second; // copy while holding lock
            }

            // ── Alerts (metadata etc.) ────────────────────────────────
            std::vector<alert*> alerts;
            ses_->pop_alerts(&alerts);
            for (alert* a : alerts) {
                if (auto* md = alert_cast<metadata_received_alert>(a)) {
                    if (!metadataDelivered && md->handle == snap.torrentHandle && snap.metaCallback) {
                        Metadata m;
                        m.id = id;
                        if (auto info = md->handle.torrent_file()) {
                            m.name          = info->name();
                            m.totalBytes    = info->total_size();
                            m.pieceSize     = info->piece_length();
                            m.pieceCount    = info->num_pieces();
                            m.fileCount     = info->num_files();
                            m.creationDate  = info->creation_date();
                            m.isPrivate     = info->priv();
                            m.isV2          = info->v2();
                        }
                        metadataDelivered = true;
                        snap.metaCallback(m);
                    }
                } else if (auto* mf = alert_cast<metadata_failed_alert>(a)) {
                    if (!metadataDelivered && mf->handle == snap.torrentHandle && snap.metaCallback) {
                        metadataDelivered = true; // deliver empty meta as failure marker
                        Metadata m; m.id = id;
                        snap.metaCallback(m);
                    }
                }
            }

            // ── Periodic stats ───────────────────────────────────────
            torrent_status st = snap.torrentHandle.status();
            Stats stats;
            stats.id           = id;
            stats.dlRate       = st.download_payload_rate;
            stats.ulRate       = st.upload_payload_rate;
            stats.pieces       = st.num_pieces;
            stats.piecesTotal  = snap.torrentHandle.torrent_file() ?
                                 snap.torrentHandle.torrent_file()->num_pieces() : 0;
            stats.progressPct  = static_cast<int>(st.progress * 100.f);
            stats.seeds        = st.num_seeds;
            stats.peers        = st.num_peers;
            stats.phase        = phase_from_state(st.state);
            snap.statsCallback(stats);

            // ── Done? (finished or seeding) ───────────────────────────
            if (st.is_seeding || st.is_finished) {
                finalise(id);   // keep files on disk
                return;
            }

            if (!snap.torrentHandle.is_valid()) {
                cancel(id);    // invalid handle; clean up
                return;
            }

            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
} // namespace tc
