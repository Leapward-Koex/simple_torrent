// torrent_core.cpp  ────────────────────────────────────────────────
#include "torrent_core.hpp"
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/alert_types.hpp>
#include <thread>
#include <chrono>

namespace tc
{
    using namespace libtorrent;
    Manager::Manager(int max) : max_(max)
    {
        settings_pack sp;
        sp.set_int(settings_pack::alert_mask,
                   alert::status_notification);
        ses_ = std::make_unique<session>(sp);
    }
    Manager::~Manager() = default;

    int Manager::start(const std::string &magnet,
                       const std::string &path,
                       StatsCb cb, MetadataCb metaCb)
    {
        std::lock_guard lk(mtx_);
        if ((int)map_.size() >= max_)
            return 0;

        add_torrent_params p;
        p.save_path = path;
        error_code ec;
        parse_magnet_uri(magnet, p, ec);
        if (ec)
            return 0;

        int id = nextId_++;
        torrent_handle h = ses_->add_torrent(p, ec);
        if (ec || !h.is_valid())
            return 0;
        map_[id] = {h, std::move(cb), std::move(metaCb)};
        std::thread(&Manager::poll, this, id).detach();
        return id;
    }

    void Manager::pause(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
            it->second.torrentHandle.pause();
    }
    void Manager::resume(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
            it->second.torrentHandle.resume();
    }
    void Manager::cancel(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
        {
            ses_->remove_torrent(it->second.torrentHandle, session::delete_files);
            map_.erase(it);
        }
    }

    void Manager::poll(int id)
    {
        bool metadataDelivered = false;

        for (;;)
        {
            Entry entrySnapshot;
            {
                std::lock_guard lk(mtx_);
                auto it = map_.find(id);
                if (it == map_.end())
                    return;
                entrySnapshot = it->second;
            }

            // ── Handle libtorrent alerts (metadata etc.)
            std::vector<alert*> alerts;
            ses_->pop_alerts(&alerts);

            for (alert* baseAlert : alerts) {
                if (auto* md = alert_cast<metadata_received_alert>(baseAlert)) {
                    if (!metadataDelivered &&
                        md->handle == entrySnapshot.torrentHandle &&
                        entrySnapshot.metaCallback)
                    {
                        Metadata meta;
                        meta.id = id;

                        auto torrentInfo = md->handle.torrent_file();
                        if (torrentInfo != nullptr) {
                            meta.name        = torrentInfo->name();
                            meta.totalBytes  = torrentInfo->total_size();
                            meta.pieceSize   = torrentInfo->piece_length();
                            meta.pieceCount  = torrentInfo->num_pieces();
                            meta.fileCount   = torrentInfo->num_files();
                            meta.creationDate= torrentInfo->creation_date();
                            meta.isPrivate   = torrentInfo->priv();
                            meta.isV2        = torrentInfo->v2();
                        }

                        metadataDelivered = true;
                        entrySnapshot.metaCallback(meta);
                    }
                }

                if (auto* mdFail = alert_cast<metadata_failed_alert>(baseAlert)) {
                    if (!metadataDelivered &&
                        mdFail->handle == entrySnapshot.torrentHandle &&
                        entrySnapshot.metaCallback)
                    {
                        metadataDelivered = true;
                        Metadata meta;
                        meta.id = id;
                        entrySnapshot.metaCallback(meta);
                    }
                }
            }

            // ── Regular progress stats
            torrent_status torrentStatus = entrySnapshot.torrentHandle.status();
            Stats stats;
            stats.id = id;
            stats.dlRate = torrentStatus.download_payload_rate;
            stats.ulRate = torrentStatus.upload_payload_rate;
            stats.pieces = torrentStatus.num_pieces;
            stats.piecesTotal = entrySnapshot.torrentHandle.torrent_file()
                                ? entrySnapshot.torrentHandle.torrent_file()->num_pieces()
                                : 0;
            stats.progressPct = int(torrentStatus.progress * 100.f);
            stats.seeds = torrentStatus.num_seeds;
            stats.peers = torrentStatus.num_peers;
            entrySnapshot.statsCallback(stats);

            if (torrentStatus.is_seeding || !entrySnapshot.torrentHandle.is_valid())
            {
                cancel(id);
                return;
            }
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
} // namespace tc
