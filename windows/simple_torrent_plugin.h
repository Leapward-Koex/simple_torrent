#ifndef FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_
#define FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace simple_torrent {

class SimpleTorrentPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  SimpleTorrentPlugin();

  virtual ~SimpleTorrentPlugin();

  // Disallow copy and assign.
  SimpleTorrentPlugin(const SimpleTorrentPlugin&) = delete;
  SimpleTorrentPlugin& operator=(const SimpleTorrentPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace simple_torrent

#endif  // FLUTTER_PLUGIN_SIMPLE_TORRENT_PLUGIN_H_
