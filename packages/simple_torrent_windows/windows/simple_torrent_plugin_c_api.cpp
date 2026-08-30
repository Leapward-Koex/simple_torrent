#include "include/simple_torrent_windows/simple_torrent_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "simple_torrent_plugin.h"

void SimpleTorrentPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  simple_torrent_windows::SimpleTorrentPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
