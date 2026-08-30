#include "torrent_manager.hpp"

#include <libtorrent/alert_types.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_flags.hpp>

#include <algorithm>
#include <climits>
#include <exception>
#include <filesystem>
#include <fstream>
#include <limits>
#include <utility>

namespace simple_torrent::native {
namespace {

constexpr auto kPollInterval = std::chrono::milliseconds(500);
constexpr auto kLifecycleTimeout = std::chrono::seconds(30);

std::string InfoHashKey(const libtorrent::info_hash_t& hashes) {
  std::string key;
  if (hashes.has_v1()) {
    key += libtorrent::aux::to_hex(hashes.v1);
  }
  key += ':';
  if (hashes.has_v2()) {
    key += libtorrent::aux::to_hex(hashes.v2);
  }
  return key;
}

libtorrent::settings_pack SettingsFor(const Config& config) {
  using libtorrent::alert;
  using libtorrent::settings_pack;

  settings_pack settings;
  settings.set_int(settings_pack::alert_mask,
                   alert::status_notification | alert::error_notification |
                       alert::storage_notification |
                       alert::tracker_notification);
  settings.set_int(settings_pack::download_rate_limit,
                   static_cast<int>(config.download_rate_limit));
  settings.set_int(settings_pack::upload_rate_limit,
                   static_cast<int>(config.upload_rate_limit));
  settings.set_int(settings_pack::connections_limit,
                   config.connections_limit);
  settings.set_bool(settings_pack::enable_dht, config.enable_dht);
  settings.set_bool(settings_pack::enable_lsd, true);
  settings.set_bool(settings_pack::enable_upnp, true);
  settings.set_bool(settings_pack::enable_natpmp, true);
  settings.set_str(settings_pack::user_agent, config.user_agent);
  return settings;
}

}  // namespace

simple_torrent_result_t ValidateConfig(const Config& config) {
  if (config.max_torrents <= 0 || config.max_torrents > 10000 ||
      config.download_rate_limit < 0 ||
      config.download_rate_limit > INT_MAX ||
      config.upload_rate_limit < 0 || config.upload_rate_limit > INT_MAX ||
      config.connections_limit <= 0 || config.connections_limit > 100000 ||
      config.user_agent.empty()) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  return SIMPLE_TORRENT_OK;
}

simple_torrent_state_t StateFromLibtorrent(
    libtorrent::torrent_status::state_t state) {
  using Status = libtorrent::torrent_status;
  switch (state) {
    case Status::checking_files:
    case Status::checking_resume_data:
      return SIMPLE_TORRENT_STATE_STARTING;
    case Status::downloading_metadata:
      return SIMPLE_TORRENT_STATE_DOWNLOADING_METADATA;
    case Status::downloading:
      return SIMPLE_TORRENT_STATE_DOWNLOADING;
    case Status::finished:
    case Status::seeding:
      return SIMPLE_TORRENT_STATE_SEEDING;
    default:
      return SIMPLE_TORRENT_STATE_ERROR;
  }
}

Manager::Manager(Config config,
                 StatsCallback stats_callback,
                 MetadataCallback metadata_callback)
    : config_(std::move(config)),
      stats_callback_(std::move(stats_callback)),
      metadata_callback_(std::move(metadata_callback)),
      session_(std::make_unique<libtorrent::session>(SettingsFor(config_))),
      poll_thread_(&Manager::Poll, this) {}

Manager::~Manager() {
  stopping_.store(true);
  if (poll_thread_.joinable()) {
    poll_thread_.join();
  }

  std::lock_guard lock(mutex_);
  for (auto& [id, entry] : entries_) {
    (void)id;
    entry->active.store(false);
  }
  entries_.clear();
}

simple_torrent_result_t Manager::UpdateConfig(const Config& config) {
  if (const auto result = ValidateConfig(config);
      result != SIMPLE_TORRENT_OK) {
    return result;
  }

  try {
    std::lock_guard lock(mutex_);
    session_->apply_settings(SettingsFor(config));
    config_ = config;
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::Start(const std::string& magnet,
                                       const std::string& destination,
                                       const std::string& display_name,
                                       std::int32_t* torrent_id) {
  if (magnet.empty() || destination.empty() || torrent_id == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }

  libtorrent::add_torrent_params params;
  params.save_path = destination;
  libtorrent::error_code error;
  libtorrent::parse_magnet_uri(magnet, params, error);
  if (error) {
    return SIMPLE_TORRENT_INVALID_TORRENT;
  }
  // The public API downloads and verifies the complete torrent. Ignore a
  // magnet `so=` selection so finished/seeding always means every payload
  // file is complete.
  params.file_priorities.clear();
  return Add(std::move(params), magnet, destination, display_name, torrent_id);
}

simple_torrent_result_t Manager::StartFromData(
    const std::uint8_t* data,
    std::size_t size,
    const std::string& destination,
    const std::string& display_name,
    std::int32_t* torrent_id) {
  if (data == nullptr || size == 0 || destination.empty() ||
      torrent_id == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }

  try {
    const auto* bytes = reinterpret_cast<const char*>(data);
    auto params = libtorrent::load_torrent_buffer(
        libtorrent::span<const char>(bytes, size));
    params.save_path = destination;
    return Add(std::move(params), {}, destination, display_name, torrent_id);
  } catch (...) {
    return SIMPLE_TORRENT_INVALID_TORRENT;
  }
}

simple_torrent_result_t Manager::StartFromFile(
    const std::string& torrent_file_path,
    const std::string& destination,
    const std::string& display_name,
    std::int32_t* torrent_id) {
  if (torrent_file_path.empty() || destination.empty() ||
      torrent_id == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }

  std::ifstream stream(std::filesystem::u8path(torrent_file_path),
                       std::ios::binary | std::ios::ate);
  if (!stream) {
    return SIMPLE_TORRENT_IO_ERROR;
  }
  const auto end = stream.tellg();
  if (end < 0 ||
      static_cast<std::uintmax_t>(end) >
          std::numeric_limits<std::size_t>::max()) {
    return SIMPLE_TORRENT_IO_ERROR;
  }
  const auto size = static_cast<std::size_t>(end);
  if (size == 0) {
    return SIMPLE_TORRENT_INVALID_TORRENT;
  }
  std::vector<std::uint8_t> bytes(size);
  stream.seekg(0, std::ios::beg);
  if (!stream.read(reinterpret_cast<char*>(bytes.data()),
                   static_cast<std::streamsize>(bytes.size()))) {
    return SIMPLE_TORRENT_IO_ERROR;
  }
  return StartFromData(bytes.data(), bytes.size(), destination, display_name,
                       torrent_id);
}

simple_torrent_result_t Manager::Add(
    libtorrent::add_torrent_params params,
    const std::string& magnet,
    const std::string& destination,
    const std::string& display_name,
    std::int32_t* torrent_id) {
  std::shared_ptr<Entry> entry;
  std::shared_ptr<const libtorrent::torrent_info> metadata = params.ti;
  const auto info_hash_key = InfoHashKey(params.info_hashes);
  std::int32_t id = 0;

  try {
    params.flags |= libtorrent::torrent_flags::duplicate_is_error;
    {
      std::lock_guard lock(mutex_);
      if (static_cast<std::int32_t>(entries_.size()) >=
          config_.max_torrents) {
        return SIMPLE_TORRENT_LIMIT_REACHED;
      }
      if (std::any_of(entries_.begin(), entries_.end(),
                      [&info_hash_key](const auto& item) {
                        return item.second->active.load() &&
                               item.second->info_hash_key == info_hash_key;
                      })) {
        return SIMPLE_TORRENT_DUPLICATE_TORRENT;
      }

      libtorrent::error_code error;
      auto handle = session_->add_torrent(params, error);
      if (error == libtorrent::errors::make_error_code(
                       libtorrent::errors::duplicate_torrent)) {
        return SIMPLE_TORRENT_DUPLICATE_TORRENT;
      }
      if (error || !handle.is_valid()) {
        return SIMPLE_TORRENT_NATIVE_ERROR;
      }

      id = next_id_++;
      entry = std::make_shared<Entry>();
      entry->handle = std::move(handle);
      entry->magnet_uri = magnet;
      entry->save_path = destination;
      entry->display_name = !display_name.empty()
                                ? display_name
                                : (metadata ? metadata->name()
                                            : "Torrent " + std::to_string(id));
      entry->info_hash_key = info_hash_key;
      entry->created_at = std::chrono::system_clock::now();
      entries_.emplace(id, entry);
    }

    *torrent_id = id;
    if (metadata) {
      DeliverMetadata(id, entry, metadata);
    }
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

std::shared_ptr<Manager::Entry> Manager::Find(std::int32_t id) const {
  std::lock_guard lock(mutex_);
  const auto iterator = entries_.find(id);
  return iterator == entries_.end() ? nullptr : iterator->second;
}

simple_torrent_result_t Manager::SetTransfersSuspended(bool suspended) {
  try {
    std::lock_guard lock(mutex_);
    const bool current = session_->is_paused();
    if (current == suspended) {
      return SIMPLE_TORRENT_OK;
    }
    if (suspended) {
      session_->pause();
    } else {
      session_->resume();
    }
    return session_->is_paused() == suspended ? SIMPLE_TORRENT_OK
                                               : SIMPLE_TORRENT_NATIVE_ERROR;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::TransfersSuspended(bool* suspended) const {
  if (suspended == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *suspended = false;
  try {
    std::lock_guard lock(mutex_);
    *suspended = session_->is_paused();
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::Pause(std::int32_t id) {
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }
  try {
    std::unique_lock lifecycle_lock(entry->lifecycle_mutex);
    if (entry->finalising || !entry->active.load()) {
      return SIMPLE_TORRENT_NATIVE_ERROR;
    }
    entry->handle.unset_flags(libtorrent::torrent_flags::auto_managed);
    entry->handle.pause();
    entry->state.store(SIMPLE_TORRENT_STATE_PAUSED);
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::Resume(std::int32_t id) {
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }
  try {
    std::unique_lock lifecycle_lock(entry->lifecycle_mutex);
    if (entry->finalising || !entry->active.load()) {
      return SIMPLE_TORRENT_NATIVE_ERROR;
    }
    {
      std::lock_guard entry_lock(entry->mutex);
      entry->handle.clear_error();
      entry->fatal_error.store(false);
      entry->last_error.clear();
      if (!entry->completion_flush_complete.load()) {
        entry->completion_flush_requested.store(false);
      }
    }
    entry->handle.set_flags(libtorrent::torrent_flags::auto_managed);
    entry->handle.resume();
    entry->state.store(SIMPLE_TORRENT_STATE_STARTING);
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::Cancel(std::int32_t id) {
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }
  try {
    std::unique_lock lifecycle_lock(entry->lifecycle_mutex);
    if (entry->finalising || !entry->active.load()) {
      return SIMPLE_TORRENT_NATIVE_ERROR;
    }
    entry->active.store(false);
    session_->remove_torrent(entry->handle, libtorrent::session::delete_files);
    lifecycle_lock.unlock();
    std::lock_guard lock(mutex_);
    const auto iterator = entries_.find(id);
    if (iterator != entries_.end() && iterator->second == entry) {
      entries_.erase(iterator);
    }
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    {
      std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
      entry->active.store(true);
    }
    RecordError(entry->handle, "Failed to cancel torrent", true);
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

simple_torrent_result_t Manager::Finalise(std::int32_t id) {
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }

  bool removal_started = false;
  try {
    {
      std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
      if (entry->finalising || !entry->active.load()) {
        return SIMPLE_TORRENT_NATIVE_ERROR;
      }
      entry->finalising = true;
      entry->pre_remove_flush_complete = false;
      entry->removed = false;
      entry->active.store(false);
    }

    // The first barrier makes all completed piece writes durable. The removal
    // barrier below then waits until libtorrent reports that no files remain
    // open, so callers may safely inspect or delete the destination afterward.
    if (entry->completion_flush_complete.load()) {
      std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
      entry->pre_remove_flush_complete = true;
    } else {
      entry->handle.flush_cache();
      {
        std::unique_lock lifecycle_lock(entry->lifecycle_mutex);
        if (!entry->lifecycle_changed.wait_for(
                lifecycle_lock, kLifecycleTimeout,
                [&entry] { return entry->pre_remove_flush_complete; })) {
          entry->finalising = false;
          entry->active.store(true);
          lifecycle_lock.unlock();
          RecordError(entry->handle,
                      "Timed out waiting for torrent disk cache to flush",
                      true);
          return SIMPLE_TORRENT_NATIVE_ERROR;
        }
      }
    }

    session_->remove_torrent(entry->handle);
    removal_started = true;
    {
      std::unique_lock lifecycle_lock(entry->lifecycle_mutex);
      if (!entry->lifecycle_changed.wait_for(
              lifecycle_lock, kLifecycleTimeout,
              [&entry] { return entry->removed; })) {
        entry->finalising = false;
        lifecycle_lock.unlock();
        {
          std::lock_guard entry_lock(entry->mutex);
          entry->last_error =
              "Timed out waiting for torrent removal confirmation";
        }
        entry->state.store(SIMPLE_TORRENT_STATE_STOPPED);
        std::lock_guard lock(mutex_);
        const auto iterator = entries_.find(id);
        if (iterator != entries_.end() && iterator->second == entry) {
          entries_.erase(iterator);
        }
        return SIMPLE_TORRENT_NATIVE_ERROR;
      }
      entry->finalising = false;
    }
    entry->state.store(SIMPLE_TORRENT_STATE_STOPPED);
    std::lock_guard lock(mutex_);
    const auto iterator = entries_.find(id);
    if (iterator != entries_.end() && iterator->second == entry) {
      entries_.erase(iterator);
    }
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    {
      std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
      entry->finalising = false;
      if (!removal_started) {
        entry->active.store(true);
      }
    }
    if (!removal_started) {
      RecordError(entry->handle, "Failed to finalise torrent", true);
    } else {
      entry->state.store(SIMPLE_TORRENT_STATE_STOPPED);
      std::lock_guard lock(mutex_);
      const auto iterator = entries_.find(id);
      if (iterator != entries_.end() && iterator->second == entry) {
        entries_.erase(iterator);
      }
    }
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
}

std::vector<std::int32_t> Manager::ActiveIds() const {
  std::lock_guard lock(mutex_);
  std::vector<std::int32_t> ids;
  ids.reserve(entries_.size());
  for (const auto& [id, entry] : entries_) {
    if (entry->active.load()) {
      ids.push_back(id);
    }
  }
  std::sort(ids.begin(), ids.end());
  return ids;
}

bool Manager::Exists(std::int32_t id) const { return Find(id) != nullptr; }

simple_torrent_result_t Manager::State(
    std::int32_t id, simple_torrent_state_t* state) const {
  if (state == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }
  *state = entry->state.load();
  return SIMPLE_TORRENT_OK;
}

simple_torrent_result_t Manager::Info(std::int32_t id,
                                      TorrentInfo* info) const {
  if (info == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }

  std::lock_guard entry_lock(entry->mutex);
  info->id = id;
  info->magnet_uri = entry->magnet_uri;
  info->save_path = entry->save_path;
  info->display_name = entry->display_name;
  info->state = entry->state.load();
  info->last_error = entry->last_error;
  info->created_at_milliseconds =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          entry->created_at.time_since_epoch())
          .count();
  return SIMPLE_TORRENT_OK;
}

simple_torrent_result_t Manager::LastError(std::int32_t id,
                                           std::string* error) const {
  if (error == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  auto entry = Find(id);
  if (!entry) {
    return SIMPLE_TORRENT_NOT_FOUND;
  }
  std::lock_guard entry_lock(entry->mutex);
  *error = entry->last_error;
  return SIMPLE_TORRENT_OK;
}

void Manager::Poll() {
  while (!stopping_.load()) {
    try {
      session_->wait_for_alert(kPollInterval);
      if (stopping_.load()) {
        break;
      }
      ProcessAlerts();
      UpdateStats();
    } catch (...) {
      // A single malformed alert, allocation failure, or platform callback
      // must not terminate the manager's polling thread.
    }
  }
}

void Manager::ProcessAlerts() {
  std::vector<libtorrent::alert*> alerts;
  session_->pop_alerts(&alerts);
  for (auto* alert : alerts) {
    if (const auto* metadata_alert =
            libtorrent::alert_cast<libtorrent::metadata_received_alert>(alert)) {
      std::int32_t id = 0;
      std::shared_ptr<Entry> entry;
      {
        std::lock_guard lock(mutex_);
        for (const auto& candidate : entries_) {
          if (candidate.second->handle == metadata_alert->handle) {
            id = candidate.first;
            entry = candidate.second;
            break;
          }
        }
      }
      if (entry && entry->active.load()) {
        DeliverMetadata(id, entry, metadata_alert->handle.torrent_file());
      }
    } else if (const auto* failed =
                   libtorrent::alert_cast<libtorrent::metadata_failed_alert>(
                       alert)) {
      // Metadata exchange can retry with another peer. Preserve the diagnostic
      // for getLastError without trapping the torrent in a fatal state.
      RecordError(failed->handle, failed->message(), false);
    } else if (const auto* tracker_error =
                   libtorrent::alert_cast<libtorrent::tracker_error_alert>(
                       alert)) {
      RecordError(tracker_error->handle, tracker_error->message(), false);
    } else if (const auto* web_seed_error =
                   libtorrent::alert_cast<libtorrent::url_seed_alert>(alert)) {
      RecordError(web_seed_error->handle, web_seed_error->message(), false);
    } else if (const auto* error =
                   libtorrent::alert_cast<libtorrent::torrent_error_alert>(
                       alert)) {
      RecordError(error->handle, error->error.message(), true);
    } else if (const auto* file_error =
                   libtorrent::alert_cast<libtorrent::file_error_alert>(
                       alert)) {
      RecordError(file_error->handle, file_error->message(), true);
    } else if (const auto* flushed =
                   libtorrent::alert_cast<libtorrent::cache_flushed_alert>(
                       alert)) {
      std::shared_ptr<Entry> entry;
      {
        std::lock_guard lock(mutex_);
        for (const auto& candidate : entries_) {
          if (candidate.second->handle == flushed->handle) {
            entry = candidate.second;
            break;
          }
        }
      }
      if (entry) {
        entry->completion_flush_complete.store(true);
        {
          std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
          if (entry->finalising) {
            entry->pre_remove_flush_complete = true;
          }
        }
        entry->lifecycle_changed.notify_all();
      }
    } else if (const auto* removed =
                   libtorrent::alert_cast<libtorrent::torrent_removed_alert>(
                       alert)) {
      std::shared_ptr<Entry> entry;
      {
        std::lock_guard lock(mutex_);
        for (const auto& candidate : entries_) {
          if (candidate.second->handle == removed->handle) {
            entry = candidate.second;
            break;
          }
        }
      }
      if (entry) {
        {
          std::lock_guard lifecycle_lock(entry->lifecycle_mutex);
          entry->removed = true;
        }
        entry->lifecycle_changed.notify_all();
      }
    }
  }
}

void Manager::UpdateStats() {
  std::vector<std::pair<std::int32_t, std::shared_ptr<Entry>>> snapshot;
  {
    std::lock_guard lock(mutex_);
    snapshot.reserve(entries_.size());
    for (const auto& item : entries_) {
      snapshot.push_back(item);
    }
  }

  for (const auto& [id, entry] : snapshot) {
    if (!entry->active.load()) {
      continue;
    }
    try {
      const auto status = entry->handle.status();
      if (status.errc && !entry->fatal_error.load()) {
        RecordError(entry->handle, status.errc.message(), true);
      }

      auto state = SIMPLE_TORRENT_STATE_ERROR;
      if (entry->fatal_error.load()) {
        state = SIMPLE_TORRENT_STATE_ERROR;
      } else if ((entry->handle.flags() & libtorrent::torrent_flags::paused) !=
                 libtorrent::torrent_flags_t{}) {
        state = SIMPLE_TORRENT_STATE_PAUSED;
      } else {
        state = StateFromLibtorrent(status.state);
        if (state == SIMPLE_TORRENT_STATE_SEEDING &&
            !entry->completion_flush_complete.load()) {
          if (!entry->completion_flush_requested.exchange(true)) {
            entry->handle.flush_cache();
          }
          // All pieces are verified, but do not advertise seeding until the
          // storage alert confirms outstanding writes are durable.
          state = SIMPLE_TORRENT_STATE_DOWNLOADING;
        }
      }
      entry->state.store(state);

      const auto metadata = entry->handle.torrent_file();
      if (status.has_metadata && metadata &&
          !entry->metadata_delivered.load()) {
        DeliverMetadata(id, entry, metadata);
      }

      Stats stats;
      stats.id = id;
      stats.download_rate = status.download_payload_rate;
      stats.upload_rate = status.upload_payload_rate;
      stats.pieces = status.num_pieces;
      stats.pieces_total = metadata ? metadata->num_pieces() : 0;
      stats.progress = status.progress;
      stats.seeds = status.num_seeds;
      stats.peers = status.num_peers;
      stats.state = state;
      if (stats_callback_ && entry->active.load()) {
        try {
          stats_callback_(stats);
        } catch (...) {
          // Callbacks are an observer boundary and cannot stop polling.
        }
      }
    } catch (const std::exception& exception) {
      RecordError(entry->handle, exception.what(), true);
    } catch (...) {
      RecordError(entry->handle, "Unknown native status error", true);
    }
  }
}

void Manager::DeliverMetadata(
    std::int32_t id,
    const std::shared_ptr<Entry>& entry,
    const std::shared_ptr<const libtorrent::torrent_info>& info) {
  if (!info || entry->metadata_delivered.exchange(true) ||
      !entry->active.load()) {
    return;
  }

  Metadata metadata;
  metadata.id = id;
  metadata.name = info->name();
  metadata.total_bytes = info->total_size();
  metadata.piece_size = info->piece_length();
  metadata.piece_count = info->num_pieces();
  metadata.creation_date = static_cast<std::int64_t>(info->creation_date());
  metadata.is_private = info->priv();
  metadata.is_v2 = info->v2();

  const auto& hashes = info->info_hashes();
  if (hashes.has_v1()) {
    metadata.v1_info_hash = libtorrent::aux::to_hex(hashes.v1);
  }
  if (hashes.has_v2()) {
    metadata.v2_info_hash = libtorrent::aux::to_hex(hashes.v2);
  }

  const auto& files = info->files();
  metadata.files.reserve(static_cast<std::size_t>(files.num_files()));
  for (std::int32_t index = 0; index < files.num_files(); ++index) {
    const libtorrent::file_index_t file_index{index};
    metadata.files.push_back(File{
        index,
        files.file_path(file_index),
        files.file_size(file_index),
        files.file_offset(file_index),
    });
  }

  {
    std::lock_guard entry_lock(entry->mutex);
    if (!entry->fatal_error.load()) {
      entry->last_error.clear();
    }
    if (entry->display_name.empty() ||
        entry->display_name.rfind("Torrent ", 0) == 0) {
      entry->display_name = metadata.name;
    }
  }

  if (metadata_callback_ && entry->active.load()) {
    try {
      metadata_callback_(metadata);
    } catch (...) {
      // Callbacks are an observer boundary and cannot stop polling.
    }
  }
}

void Manager::RecordError(const libtorrent::torrent_handle& handle,
                          const std::string& message,
                          bool fatal) {
  std::int32_t id = 0;
  std::shared_ptr<Entry> entry;
  {
    std::lock_guard lock(mutex_);
    for (const auto& candidate : entries_) {
      if (candidate.second->handle == handle) {
        id = candidate.first;
        entry = candidate.second;
        break;
      }
    }
  }
  if (!entry) {
    return;
  }
  {
    std::lock_guard entry_lock(entry->mutex);
    if (!fatal && entry->fatal_error.load()) {
      return;
    }
    entry->last_error = message;
    if (fatal) {
      entry->fatal_error.store(true);
    }
  }
  if (fatal) {
    entry->state.store(SIMPLE_TORRENT_STATE_ERROR);
    EmitErrorStats(id, entry);
  }
}

void Manager::EmitErrorStats(std::int32_t id,
                             const std::shared_ptr<Entry>& entry) {
  if (!stats_callback_ || !entry->active.load()) {
    return;
  }
  Stats stats;
  stats.id = id;
  stats.state = SIMPLE_TORRENT_STATE_ERROR;
  try {
    const auto status = entry->handle.status();
    const auto metadata = entry->handle.torrent_file();
    stats.download_rate = status.download_payload_rate;
    stats.upload_rate = status.upload_payload_rate;
    stats.pieces = status.num_pieces;
    stats.pieces_total = metadata ? metadata->num_pieces() : 0;
    stats.progress = status.progress;
    stats.seeds = status.num_seeds;
    stats.peers = status.num_peers;
  } catch (...) {
    // The zero-initialized counters are still a valid observable error event.
  }
  try {
    stats_callback_(stats);
  } catch (...) {
    // Preserve the fatal latch even if a platform observer rejects the event.
  }
}

}  // namespace simple_torrent::native
