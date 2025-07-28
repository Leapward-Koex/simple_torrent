#include "simple_torrent_plugin.h"
#include "../../shared/torrent_core/torrent_core.hpp"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>

#include <memory>
#include <unordered_map>
#include <sstream>

namespace simple_torrent {

// Helper function to convert TorrentState to string
std::string StateToString(tc::TorrentState state) {
  switch (state) {
    case tc::TorrentState::Starting: return "starting";
    case tc::TorrentState::DownloadingMetadata: return "downloading_metadata";
    case tc::TorrentState::Downloading: return "downloading";
    case tc::TorrentState::Seeding: return "seeding";
    case tc::TorrentState::Paused: return "paused";
    case tc::TorrentState::Error: return "error";
    case tc::TorrentState::Stopped: return "stopped";
    default: return "unknown";
  }
}

// static
void SimpleTorrentPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "simple_torrent/methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SimpleTorrentPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

SimpleTorrentPlugin::SimpleTorrentPlugin(flutter::PluginRegistrarWindows *registrar) 
    : registrar_(registrar) {
  manager_ = std::make_unique<tc::Manager>();
  
  // Set up progress event channel (matches Dart EventChannel name)
  auto progress_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "simple_torrent/progress",
      &flutter::StandardMethodCodec::GetInstance());
      
  auto progress_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
             -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        stats_event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
             -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        stats_event_sink_.reset();
        return nullptr;
      });
  
  progress_channel->SetStreamHandler(std::move(progress_handler));
  
  // Set up metadata event channel (matches Dart EventChannel name)
  auto metadata_channel = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
      registrar->messenger(), "simple_torrent/metadata",
      &flutter::StandardMethodCodec::GetInstance());
      
  auto metadata_handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [this](const flutter::EncodableValue* arguments,
             std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
             -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        metadata_event_sink_ = std::move(events);
        return nullptr;
      },
      [this](const flutter::EncodableValue* arguments)
             -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
        metadata_event_sink_.reset();
        return nullptr;
      });
  
  metadata_channel->SetStreamHandler(std::move(metadata_handler));
}

SimpleTorrentPlugin::~SimpleTorrentPlugin() {}

void SimpleTorrentPlugin::SendStatsEvent(const tc::Stats& stats) {
  if (stats_event_sink_) {
    flutter::EncodableMap stats_map;
    stats_map[flutter::EncodableValue("eventType")] = flutter::EncodableValue("stats");
    stats_map[flutter::EncodableValue("id")] = flutter::EncodableValue(stats.id);
    stats_map[flutter::EncodableValue("download_rate")] = flutter::EncodableValue(stats.dlRate);
    stats_map[flutter::EncodableValue("upload_rate")] = flutter::EncodableValue(stats.ulRate);
    stats_map[flutter::EncodableValue("pieces")] = flutter::EncodableValue(stats.pieces);
    stats_map[flutter::EncodableValue("pieces_total")] = flutter::EncodableValue(stats.piecesTotal);
    stats_map[flutter::EncodableValue("progress")] = flutter::EncodableValue(stats.progressPct);
    stats_map[flutter::EncodableValue("seeds")] = flutter::EncodableValue(stats.seeds);
    stats_map[flutter::EncodableValue("peers")] = flutter::EncodableValue(stats.peers);
    stats_map[flutter::EncodableValue("phase")] = flutter::EncodableValue(stats.phase);
    stats_map[flutter::EncodableValue("state")] = flutter::EncodableValue(StateToString(stats.state));
    
    stats_event_sink_->Success(flutter::EncodableValue(stats_map));
  }
}

void SimpleTorrentPlugin::SendMetadataEvent(const tc::Metadata& metadata) {
  if (metadata_event_sink_) {
    flutter::EncodableMap metadata_map;
    metadata_map[flutter::EncodableValue("eventType")] = flutter::EncodableValue("metadata");
    metadata_map[flutter::EncodableValue("id")] = flutter::EncodableValue(metadata.id);
    metadata_map[flutter::EncodableValue("name")] = flutter::EncodableValue(metadata.name);
    metadata_map[flutter::EncodableValue("total_bytes")] = flutter::EncodableValue(static_cast<int64_t>(metadata.totalBytes));
    metadata_map[flutter::EncodableValue("piece_size")] = flutter::EncodableValue(metadata.pieceSize);
    metadata_map[flutter::EncodableValue("piece_count")] = flutter::EncodableValue(metadata.pieceCount);
    metadata_map[flutter::EncodableValue("file_count")] = flutter::EncodableValue(metadata.fileCount);
    metadata_map[flutter::EncodableValue("creation_date")] = flutter::EncodableValue(static_cast<int64_t>(metadata.creationDate));
    metadata_map[flutter::EncodableValue("private")] = flutter::EncodableValue(metadata.isPrivate);
    metadata_map[flutter::EncodableValue("v2")] = flutter::EncodableValue(metadata.isV2);
    
    metadata_event_sink_->Success(flutter::EncodableValue(metadata_map));
  }
}

void SimpleTorrentPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  
  const std::string& method_name = method_call.method_name();
  
  if (method_name == "init") {
    // Handle initialization with config
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (arguments) {
      auto config_it = arguments->find(flutter::EncodableValue("config"));
      if (config_it != arguments->end()) {
        const auto* config_map = std::get_if<flutter::EncodableMap>(&config_it->second);
        if (config_map) {
          tc::ManagerConfig config;
          
          auto max_torrents_it = config_map->find(flutter::EncodableValue("maxTorrents"));
          if (max_torrents_it != config_map->end()) {
            if (const auto* value = std::get_if<int>(&max_torrents_it->second)) {
              config.maxTorrents = *value;
            }
          }
          
          auto max_dl_rate_it = config_map->find(flutter::EncodableValue("maxDownloadRate"));
          if (max_dl_rate_it != config_map->end()) {
            if (const auto* value = std::get_if<int>(&max_dl_rate_it->second)) {
              config.maxDownloadRate = *value;
            }
          }
          
          auto max_ul_rate_it = config_map->find(flutter::EncodableValue("maxUploadRate"));
          if (max_ul_rate_it != config_map->end()) {
            if (const auto* value = std::get_if<int>(&max_ul_rate_it->second)) {
              config.maxUploadRate = *value;
            }
          }
          
          auto enable_dht_it = config_map->find(flutter::EncodableValue("enableDHT"));
          if (enable_dht_it != config_map->end()) {
            if (const auto* value = std::get_if<bool>(&enable_dht_it->second)) {
              config.enableDHT = *value;
            }
          }
          
          auto user_agent_it = config_map->find(flutter::EncodableValue("userAgent"));
          if (user_agent_it != config_map->end()) {
            if (const auto* value = std::get_if<std::string>(&user_agent_it->second)) {
              config.userAgent = *value;
            }
          }
          
          manager_->applyConfig(config);
        }
      }
    }
    result->Success(flutter::EncodableValue());
  }
  else if (method_name == "start") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto magnet_it = arguments->find(flutter::EncodableValue("magnet"));
    auto dest_it = arguments->find(flutter::EncodableValue("destination"));
    
    if (magnet_it == arguments->end() || dest_it == arguments->end()) {
      result->Error("INVALID_ARGS", "magnet and destination are required");
      return;
    }
    
    const auto* magnet = std::get_if<std::string>(&magnet_it->second);
    const auto* destination = std::get_if<std::string>(&dest_it->second);
    
    if (!magnet || !destination) {
      result->Error("INVALID_ARGS", "magnet and destination must be strings");
      return;
    }
    
    std::string display_name;
    auto name_it = arguments->find(flutter::EncodableValue("displayName"));
    if (name_it != arguments->end()) {
      if (const auto* name = std::get_if<std::string>(&name_it->second)) {
        display_name = *name;
      }
    }
    
    auto stats_callback = [this](const tc::Stats& stats) {
      SendStatsEvent(stats);
    };
    
    auto metadata_callback = [this](const tc::Metadata& metadata) {
      SendMetadataEvent(metadata);
    };
    
    int torrent_id = manager_->start(*magnet, *destination, stats_callback, metadata_callback, display_name);
    
    if (torrent_id > 0) {
      std::lock_guard<std::mutex> lock(callbacks_mutex_);
      callbacks_[torrent_id] = std::make_pair(stats_callback, metadata_callback);
      result->Success(flutter::EncodableValue(torrent_id));
    } else {
      result->Error("FAILED", "Could not start torrent");
    }
  }
  else if (method_name == "pause") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    manager_->pause(*id);
    result->Success(flutter::EncodableValue());
  }
  else if (method_name == "resume") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    manager_->resume(*id);
    result->Success(flutter::EncodableValue());
  }
  else if (method_name == "cancel") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    manager_->cancel(*id);
    std::lock_guard<std::mutex> lock(callbacks_mutex_);
    callbacks_.erase(*id);
    result->Success(flutter::EncodableValue());
  }
  else if (method_name == "finalise") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    manager_->finalise(*id);
    std::lock_guard<std::mutex> lock(callbacks_mutex_);
    callbacks_.erase(*id);
    result->Success(flutter::EncodableValue());
  }
  else if (method_name == "getActiveTorrentIds") {
    auto ids = manager_->getActiveTorrentIds();
    flutter::EncodableList result_list;
    for (int id : ids) {
      result_list.push_back(flutter::EncodableValue(id));
    }
    result->Success(flutter::EncodableValue(result_list));
  }
  else if (method_name == "exists") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    bool exists = manager_->exists(*id);
    result->Success(flutter::EncodableValue(exists));
  }
  else if (method_name == "getState") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    tc::TorrentState state = manager_->getState(*id);
    std::string state_str;
    switch (state) {
      case tc::TorrentState::Starting: state_str = "starting"; break;
      case tc::TorrentState::DownloadingMetadata: state_str = "downloading_metadata"; break;
      case tc::TorrentState::Downloading: state_str = "downloading"; break;
      case tc::TorrentState::Seeding: state_str = "seeding"; break;
      case tc::TorrentState::Paused: state_str = "paused"; break;
      case tc::TorrentState::Error: state_str = "error"; break;
      case tc::TorrentState::Stopped: state_str = "stopped"; break;
      default: state_str = "unknown"; break;
    }
    result->Success(flutter::EncodableValue(state_str));
  }
  else if (method_name == "getTorrentInfo") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    try {
      tc::TorrentInfo torrent_info = manager_->getTorrentInfo(*id);
      
      // Convert createdAt time_point to milliseconds since epoch
      auto time_since_epoch = torrent_info.createdAt.time_since_epoch();
      auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(time_since_epoch).count();
      
      flutter::EncodableMap info_map;
      info_map[flutter::EncodableValue("id")] = flutter::EncodableValue(torrent_info.id);
      info_map[flutter::EncodableValue("magnetUri")] = flutter::EncodableValue(torrent_info.magnetUri);
      info_map[flutter::EncodableValue("savePath")] = flutter::EncodableValue(torrent_info.savePath);
      info_map[flutter::EncodableValue("displayName")] = flutter::EncodableValue(torrent_info.displayName);
      info_map[flutter::EncodableValue("state")] = flutter::EncodableValue(StateToString(torrent_info.state));
      info_map[flutter::EncodableValue("lastError")] = flutter::EncodableValue(torrent_info.lastError);
      info_map[flutter::EncodableValue("createdAt")] = flutter::EncodableValue(static_cast<int64_t>(millis));
      
      result->Success(flutter::EncodableValue(info_map));
    } catch (const std::exception& e) {
      result->Error("NOT_FOUND", e.what());
    }
  }
  else if (method_name == "getLastError") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGS", "Arguments must be a map");
      return;
    }
    
    auto id_it = arguments->find(flutter::EncodableValue("id"));
    if (id_it == arguments->end()) {
      result->Error("INVALID_ARGS", "id is required");
      return;
    }
    
    const auto* id = std::get_if<int>(&id_it->second);
    if (!id) {
      result->Error("INVALID_ARGS", "id must be an integer");
      return;
    }
    
    std::string error = manager_->getLastError(*id);
    result->Success(flutter::EncodableValue(error));
  }
  else {
    result->NotImplemented();
  }
}

}  // namespace simple_torrent
