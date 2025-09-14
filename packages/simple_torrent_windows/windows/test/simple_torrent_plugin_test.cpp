#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "simple_torrent_plugin.h"

namespace simple_torrent {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

// Mock registrar for testing
class MockPluginRegistrarWindows : public flutter::PluginRegistrarWindows {
public:
  flutter::BinaryMessenger* messenger() override { return nullptr; }
  flutter::TextureRegistrar* texture_registrar() override { return nullptr; }
  void AddPlugin(std::unique_ptr<flutter::Plugin> plugin) override {}
};

}  // namespace

TEST(SimpleTorrentPlugin, CanBeConstructed) {
  MockPluginRegistrarWindows registrar;
  SimpleTorrentPlugin plugin(&registrar);
  
  // Test that the plugin can be constructed successfully
  EXPECT_TRUE(true);
}

}  // namespace test
}  // namespace simple_torrent
