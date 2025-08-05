#ifndef FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_
#define FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>

#include <memory>
#include <unordered_map>
#include <functional>
#include <mutex>

// Forward declaration
namespace tc {
  class Manager;
  struct Stats;
  struct Metadata;
}

namespace simple_torrent {

class SimpleTorrentPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SimpleTorrentPlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~SimpleTorrentPlugin();

  // Disallow copy and assign.
  SimpleTorrentPlugin(const SimpleTorrentPlugin&) = delete;
  SimpleTorrentPlugin& operator=(const SimpleTorrentPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // Event channel handlers
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> stats_event_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> metadata_event_sink_;
  
  // Callback handlers
  void SendStatsEvent(const tc::Stats& stats);
  void SendMetadataEvent(const tc::Metadata& metadata);
  
  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<tc::Manager> manager_;
  std::unordered_map<int, std::pair<std::function<void(const tc::Stats&)>, 
                                   std::function<void(const tc::Metadata&)>>> callbacks_;
  std::mutex callbacks_mutex_;
};

}  // namespace simple_torrent

#endif  // FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_
