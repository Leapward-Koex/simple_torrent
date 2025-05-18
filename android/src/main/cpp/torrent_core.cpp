// torrent_core.cpp  ────────────────────────────────────────────────
#include "torrent_core.hpp"
#include <libtorrent/magnet_uri.hpp>
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
                       StatsCb cb)
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
        map_[id] = {h, std::move(cb)};
        std::thread(&Manager::poll, this, id).detach();
        return id;
    }

    void Manager::pause(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
            it->second.h.pause();
    }
    void Manager::resume(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
            it->second.h.resume();
    }
    void Manager::cancel(int id)
    {
        std::lock_guard lk(mtx_);
        auto it = map_.find(id);
        if (it != map_.end())
        {
            ses_->remove_torrent(it->second.h, session::delete_files);
            map_.erase(it);
        }
    }

    void Manager::poll(int id)
    {
        for (;;)
        {
            Entry e;
            {
                std::lock_guard lk(mtx_);
                auto it = map_.find(id);
                if (it == map_.end())
                    return;
                e = it->second;
            }
            torrent_status st = e.h.status();
            Stats s;
            s.id = id;
            s.dlRate = st.download_payload_rate;
            s.ulRate = st.upload_payload_rate;
            s.pieces = st.num_pieces;
            s.piecesTotal = e.h.torrent_file()
                                ? e.h.torrent_file()->num_pieces()
                                : 0;
            s.progressPct = int(st.progress * 100.f);
            s.seeds = st.num_seeds;
            s.peers = st.num_peers;
            e.cb(s);

            if (st.is_seeding || !e.h.is_valid())
            {
                cancel(id);
                return;
            }
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }
} // namespace tc
