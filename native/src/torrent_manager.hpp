#pragma once

#include "simple_torrent_native.h"

#include <libtorrent/session.hpp>
#include <libtorrent/torrent_handle.hpp>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace simple_torrent::native {

struct Config {
  std::int32_t max_torrents = 20;
  std::int64_t download_rate_limit = 0;
  std::int64_t upload_rate_limit = 0;
  std::int32_t connections_limit = 200;
  bool enable_dht = true;
  std::string user_agent = "simple_torrent/2.0.0";
};

struct Stats {
  std::int32_t id = 0;
  std::int64_t download_rate = 0;
  std::int64_t upload_rate = 0;
  std::int32_t pieces = 0;
  std::int32_t pieces_total = 0;
  double progress = 0;
  std::int32_t seeds = 0;
  std::int32_t peers = 0;
  simple_torrent_state_t state = SIMPLE_TORRENT_STATE_STARTING;
};

struct File {
  std::int32_t index = 0;
  std::string path;
  std::int64_t size = 0;
  std::int64_t offset = 0;
};

struct Metadata {
  std::int32_t id = 0;
  std::string name;
  std::int64_t total_bytes = 0;
  std::int32_t piece_size = 0;
  std::int32_t piece_count = 0;
  std::int64_t creation_date = 0;
  bool is_private = false;
  bool is_v2 = false;
  std::string v1_info_hash;
  std::string v2_info_hash;
  std::vector<File> files;
};

struct TorrentInfo {
  std::int32_t id = 0;
  std::string magnet_uri;
  std::string save_path;
  std::string display_name;
  simple_torrent_state_t state = SIMPLE_TORRENT_STATE_STARTING;
  std::string last_error;
  std::int64_t created_at_milliseconds = 0;
};

using StatsCallback = std::function<void(const Stats&)>;
using MetadataCallback = std::function<void(const Metadata&)>;

class Manager {
 public:
  Manager(Config config,
          StatsCallback stats_callback,
          MetadataCallback metadata_callback);
  ~Manager();

  Manager(const Manager&) = delete;
  Manager& operator=(const Manager&) = delete;

  simple_torrent_result_t UpdateConfig(const Config& config);
  simple_torrent_result_t Start(const std::string& magnet,
                                const std::string& destination,
                                const std::string& display_name,
                                std::int32_t* torrent_id);
  simple_torrent_result_t StartFromData(const std::uint8_t* data,
                                        std::size_t size,
                                        const std::string& destination,
                                        const std::string& display_name,
                                        std::int32_t* torrent_id);
  simple_torrent_result_t StartFromFile(const std::string& torrent_file_path,
                                        const std::string& destination,
                                        const std::string& display_name,
                                        std::int32_t* torrent_id);

  simple_torrent_result_t SetTransfersSuspended(bool suspended);
  simple_torrent_result_t TransfersSuspended(bool* suspended) const;
  simple_torrent_result_t Pause(std::int32_t id);
  simple_torrent_result_t Resume(std::int32_t id);
  simple_torrent_result_t Cancel(std::int32_t id);
  simple_torrent_result_t Finalise(std::int32_t id);
  std::vector<std::int32_t> ActiveIds() const;
  bool Exists(std::int32_t id) const;
  simple_torrent_result_t State(std::int32_t id,
                                simple_torrent_state_t* state) const;
  simple_torrent_result_t Info(std::int32_t id, TorrentInfo* info) const;
  simple_torrent_result_t LastError(std::int32_t id,
                                    std::string* error) const;

 private:
  struct Entry {
    libtorrent::torrent_handle handle;
    std::string magnet_uri;
    std::string save_path;
    std::string display_name;
    std::string info_hash_key;
    std::atomic<simple_torrent_state_t> state{SIMPLE_TORRENT_STATE_STARTING};
    std::atomic<bool> active{true};
    std::atomic<bool> metadata_delivered{false};
    std::atomic<bool> fatal_error{false};
    std::atomic<bool> completion_flush_requested{false};
    std::atomic<bool> completion_flush_complete{false};
    std::string last_error;
    std::chrono::system_clock::time_point created_at;
    mutable std::mutex mutex;
    std::mutex lifecycle_mutex;
    std::condition_variable lifecycle_changed;
    bool finalising = false;
    bool pre_remove_flush_complete = false;
    bool removed = false;
  };

  simple_torrent_result_t Add(
      libtorrent::add_torrent_params params,
      const std::string& magnet,
      const std::string& destination,
      const std::string& display_name,
      std::int32_t* torrent_id);
  void Poll();
  void ProcessAlerts();
  void UpdateStats();
  void DeliverMetadata(std::int32_t id,
                       const std::shared_ptr<Entry>& entry,
                       const std::shared_ptr<const libtorrent::torrent_info>& info);
  void RecordError(const libtorrent::torrent_handle& handle,
                   const std::string& message,
                   bool fatal);
  void EmitErrorStats(std::int32_t id,
                      const std::shared_ptr<Entry>& entry);
  std::shared_ptr<Entry> Find(std::int32_t id) const;

  mutable std::mutex mutex_;
  Config config_;
  StatsCallback stats_callback_;
  MetadataCallback metadata_callback_;
  std::unique_ptr<libtorrent::session> session_;
  std::unordered_map<std::int32_t, std::shared_ptr<Entry>> entries_;
  std::int32_t next_id_ = 1;
  std::atomic<bool> stopping_{false};
  std::thread poll_thread_;
};

simple_torrent_result_t ValidateConfig(const Config& config);
simple_torrent_state_t StateFromLibtorrent(
    libtorrent::torrent_status::state_t state);

}  // namespace simple_torrent::native
