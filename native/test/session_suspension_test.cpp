#include "simple_torrent_native.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <string>
#include <thread>

namespace {

constexpr char kTorrentData[] =
    "d4:infod6:lengthi1e4:name8:test.bin12:piece lengthi16384e"
    "6:pieces20:01234567890123456789ee";

bool Check(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "FAILED: " << description << '\n';
    return false;
  }
  std::cout << "PASS: " << description << '\n';
  return true;
}

}  // namespace

int main() {
  static_assert(SIMPLE_TORRENT_NATIVE_ABI_VERSION == 2u);
  bool ok = true;

  simple_torrent_config_t config;
  simple_torrent_config_init(&config);
  config.enable_dht = 0;

  simple_torrent_manager_t* manager = nullptr;
  ok &= Check(simple_torrent_manager_create(
                  &config, nullptr, nullptr, nullptr, &manager) ==
                  SIMPLE_TORRENT_OK &&
              manager != nullptr,
              "manager is created");
  if (manager == nullptr) {
    return 1;
  }

  std::uint8_t suspended = 1;
  ok &= Check(simple_torrent_manager_transfers_suspended(manager, &suspended) ==
                  SIMPLE_TORRENT_OK &&
              suspended == 0,
              "initial state is not suspended");
  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 0) ==
                  SIMPLE_TORRENT_OK,
              "initial repeated resume is idempotent");
  ok &= Check(simple_torrent_manager_set_transfers_suspended(nullptr, 1) ==
                  SIMPLE_TORRENT_INVALID_ARGUMENT,
              "null manager is rejected");
  suspended = 1;
  ok &= Check(simple_torrent_manager_transfers_suspended(nullptr, &suspended) ==
                      SIMPLE_TORRENT_INVALID_ARGUMENT &&
                  suspended == 0,
              "null manager query is rejected and clears its output");
  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 2) ==
                  SIMPLE_TORRENT_INVALID_ARGUMENT,
              "non-boolean suspension value is rejected");
  ok &= Check(simple_torrent_manager_transfers_suspended(manager, nullptr) ==
                  SIMPLE_TORRENT_INVALID_ARGUMENT,
              "null suspension output is rejected");

  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 1) ==
                  SIMPLE_TORRENT_OK,
              "session suspends");
  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 1) ==
                  SIMPLE_TORRENT_OK,
              "repeated suspension is idempotent");
  suspended = 0;
  ok &= Check(simple_torrent_manager_transfers_suspended(manager, &suspended) ==
                  SIMPLE_TORRENT_OK &&
              suspended == 1,
              "suspended state is queryable");

  config.connections_limit = 50;
  ok &= Check(simple_torrent_manager_update_config(manager, &config) ==
                  SIMPLE_TORRENT_OK,
              "configuration updates while suspended");
  suspended = 0;
  ok &= Check(simple_torrent_manager_transfers_suspended(manager, &suspended) ==
                  SIMPLE_TORRENT_OK &&
              suspended == 1,
              "configuration update preserves suspension");

  const auto unique = std::to_string(
      std::chrono::steady_clock::now().time_since_epoch().count());
  const auto destination =
      std::filesystem::temp_directory_path() /
      std::filesystem::path("simple-torrent-suspension-test-" + unique);
  std::filesystem::create_directories(destination);
  const auto destination_utf8 = destination.u8string();

  std::int32_t torrent_id = 0;
  ok &= Check(simple_torrent_manager_start_from_data(
                  manager,
                  reinterpret_cast<const std::uint8_t*>(kTorrentData),
                  sizeof(kTorrentData) - 1, destination_utf8.c_str(), nullptr,
                  &torrent_id) == SIMPLE_TORRENT_OK &&
              torrent_id > 0,
              "torrent is accepted while suspended");

  std::int32_t* ids = nullptr;
  std::size_t count = 0;
  ok &= Check(simple_torrent_manager_active_ids(manager, &ids, &count) ==
                  SIMPLE_TORRENT_OK &&
              count == 1 && ids != nullptr && ids[0] == torrent_id,
              "queued torrent remains active");
  simple_torrent_active_ids_free(ids);

  ok &= Check(simple_torrent_manager_pause(manager, torrent_id) ==
                  SIMPLE_TORRENT_OK,
              "torrent can be individually paused while session is suspended");
  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 0) ==
                  SIMPLE_TORRENT_OK,
              "session resumes");
  for (int observation = 0; observation < 3; ++observation) {
    std::this_thread::sleep_for(std::chrono::milliseconds(600));
    simple_torrent_state_t state = SIMPLE_TORRENT_STATE_ERROR;
    ok &= Check(simple_torrent_manager_state(manager, torrent_id, &state) ==
                    SIMPLE_TORRENT_OK &&
                state == SIMPLE_TORRENT_STATE_PAUSED,
                "session resume preserves individual pause state");
  }
  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 0) ==
                  SIMPLE_TORRENT_OK,
              "repeated resume is idempotent");

  ok &= Check(simple_torrent_manager_set_transfers_suspended(manager, 1) ==
                  SIMPLE_TORRENT_OK,
              "manager may be destroyed while suspended");
  simple_torrent_manager_destroy(manager);
  std::error_code ignored;
  std::filesystem::remove_all(destination, ignored);

  return ok ? 0 : 1;
}
