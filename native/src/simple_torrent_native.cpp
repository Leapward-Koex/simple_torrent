#include "simple_torrent_native.h"

#include "torrent_manager.hpp"

#include <boost/version.hpp>
#include <libtorrent/version.hpp>
#include <openssl/opensslv.h>

#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <utility>
#include <vector>

#define STN_STRINGIFY_INNER(value) #value
#define STN_STRINGIFY(value) STN_STRINGIFY_INNER(value)
#define STN_LIBTORRENT_SEMVER                                            \
  STN_STRINGIFY(LIBTORRENT_VERSION_MAJOR) "."                          \
      STN_STRINGIFY(LIBTORRENT_VERSION_MINOR) "."                      \
          STN_STRINGIFY(LIBTORRENT_VERSION_TINY)

using NativeManager = simple_torrent::native::Manager;
using NativeConfig = simple_torrent::native::Config;

struct simple_torrent_manager {
  simple_torrent_stats_callback_t stats_callback = nullptr;
  simple_torrent_metadata_callback_t metadata_callback = nullptr;
  void* user_data = nullptr;
  std::unique_ptr<NativeManager> implementation;
};

namespace {

constexpr char kVersion[] =
    "simple_torrent_native/2.0.0 libtorrent/" STN_LIBTORRENT_SEMVER
    " OpenSSL/" OPENSSL_VERSION_STR " Boost/" BOOST_LIB_VERSION;
constexpr char kBuildInfo[] =
    "simple_torrent=2.0.0;abi=2;libtorrent=" STN_LIBTORRENT_SEMVER
    ";boost=" BOOST_LIB_VERSION ";openssl=" OPENSSL_VERSION_STR;

bool IsUtf8(const char* value) {
  if (value == nullptr) {
    return false;
  }
  const auto* bytes = reinterpret_cast<const unsigned char*>(value);
  while (*bytes != 0) {
    if (*bytes <= 0x7f) {
      ++bytes;
      continue;
    }

    int continuation_count = 0;
    std::uint32_t code_point = 0;
    if ((*bytes & 0xe0) == 0xc0) {
      continuation_count = 1;
      code_point = *bytes & 0x1f;
      if (code_point < 2) {
        return false;
      }
    } else if ((*bytes & 0xf0) == 0xe0) {
      continuation_count = 2;
      code_point = *bytes & 0x0f;
    } else if ((*bytes & 0xf8) == 0xf0) {
      continuation_count = 3;
      code_point = *bytes & 0x07;
    } else {
      return false;
    }
    ++bytes;
    for (int index = 0; index < continuation_count; ++index, ++bytes) {
      if ((*bytes & 0xc0) != 0x80) {
        return false;
      }
      code_point = (code_point << 6) | (*bytes & 0x3f);
    }
    if ((continuation_count == 2 && code_point < 0x800) ||
        (continuation_count == 3 && code_point < 0x10000) ||
        (code_point >= 0xd800 && code_point <= 0xdfff) ||
        code_point > 0x10ffff) {
      return false;
    }
  }
  return true;
}

simple_torrent_result_t ConvertConfig(const simple_torrent_config_t* input,
                                      NativeConfig* output) {
  if (output == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  if (input == nullptr) {
    *output = NativeConfig{};
    return SIMPLE_TORRENT_OK;
  }
  if (input->struct_size < sizeof(simple_torrent_config_t) ||
      input->user_agent == nullptr || !IsUtf8(input->user_agent) ||
      input->enable_dht > 1) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }

  output->max_torrents = input->max_torrents;
  output->download_rate_limit = input->download_rate_limit;
  output->upload_rate_limit = input->upload_rate_limit;
  output->connections_limit = input->connections_limit;
  output->enable_dht = input->enable_dht != 0;
  output->user_agent = input->user_agent;
  return simple_torrent::native::ValidateConfig(*output);
}

char* CopyString(const std::string& value) {
  if (value.size() == std::numeric_limits<std::size_t>::max()) {
    return nullptr;
  }
  auto* copy = static_cast<char*>(std::malloc(value.size() + 1));
  if (copy == nullptr) {
    return nullptr;
  }
  std::memcpy(copy, value.data(), value.size());
  copy[value.size()] = '\0';
  return copy;
}

bool IsOptionalUtf8(const char* value) {
  return value == nullptr || IsUtf8(value);
}

std::string OptionalString(const char* value) {
  return value == nullptr ? std::string{} : std::string(value);
}

simple_torrent_result_t CheckManager(simple_torrent_manager_t* manager) {
  return manager != nullptr && manager->implementation
             ? SIMPLE_TORRENT_OK
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
}

void ForwardStats(simple_torrent_manager_t* manager,
                  const simple_torrent::native::Stats& stats) {
  if (manager->stats_callback == nullptr) {
    return;
  }
  const simple_torrent_stats_t event{
      stats.id,
      stats.download_rate,
      stats.upload_rate,
      stats.pieces,
      stats.pieces_total,
      stats.progress,
      stats.seeds,
      stats.peers,
      stats.state,
  };
  try {
    manager->stats_callback(manager->user_data, &event);
  } catch (...) {
    // Never permit a platform callback exception to cross the C ABI boundary.
  }
}

void ForwardMetadata(simple_torrent_manager_t* manager,
                     const simple_torrent::native::Metadata& metadata) {
  if (manager->metadata_callback == nullptr) {
    return;
  }

  std::vector<simple_torrent_file_t> files;
  files.reserve(metadata.files.size());
  for (const auto& file : metadata.files) {
    files.push_back(simple_torrent_file_t{
        file.index,
        file.path.c_str(),
        file.size,
        file.offset,
    });
  }

  const simple_torrent_metadata_t event{
      metadata.id,
      metadata.name.c_str(),
      metadata.total_bytes,
      metadata.piece_size,
      metadata.piece_count,
      static_cast<std::int32_t>(files.size()),
      metadata.creation_date,
      static_cast<std::uint8_t>(metadata.is_private),
      static_cast<std::uint8_t>(metadata.is_v2),
      metadata.v1_info_hash.c_str(),
      metadata.v2_info_hash.c_str(),
      files.data(),
      files.size(),
  };
  try {
    manager->metadata_callback(manager->user_data, &event);
  } catch (...) {
    // Never permit a platform callback exception to cross the C ABI boundary.
  }
}

}  // namespace

extern "C" {

uint32_t simple_torrent_native_abi_version(void) {
  return SIMPLE_TORRENT_NATIVE_ABI_VERSION;
}

const char* simple_torrent_native_version(void) { return kVersion; }

const char* simple_torrent_native_build_info(void) { return kBuildInfo; }

const char* simple_torrent_state_name(simple_torrent_state_t state) {
  switch (state) {
    case SIMPLE_TORRENT_STATE_STARTING:
      return "starting";
    case SIMPLE_TORRENT_STATE_DOWNLOADING_METADATA:
      return "downloadingMetadata";
    case SIMPLE_TORRENT_STATE_DOWNLOADING:
      return "downloading";
    case SIMPLE_TORRENT_STATE_SEEDING:
      return "seeding";
    case SIMPLE_TORRENT_STATE_PAUSED:
      return "paused";
    case SIMPLE_TORRENT_STATE_ERROR:
      return "error";
    case SIMPLE_TORRENT_STATE_STOPPED:
      return "stopped";
    default:
      return "unknown";
  }
}

const char* simple_torrent_result_name(simple_torrent_result_t result) {
  switch (result) {
    case SIMPLE_TORRENT_OK:
      return "ok";
    case SIMPLE_TORRENT_INVALID_ARGUMENT:
      return "invalidArgument";
    case SIMPLE_TORRENT_NOT_FOUND:
      return "notFound";
    case SIMPLE_TORRENT_LIMIT_REACHED:
      return "limitReached";
    case SIMPLE_TORRENT_INVALID_TORRENT:
      return "invalidTorrent";
    case SIMPLE_TORRENT_IO_ERROR:
      return "ioError";
    case SIMPLE_TORRENT_NATIVE_ERROR:
      return "nativeError";
    case SIMPLE_TORRENT_DUPLICATE_TORRENT:
      return "duplicateTorrent";
    default:
      return "unknown";
  }
}

void simple_torrent_config_init(simple_torrent_config_t* config) {
  if (config == nullptr) {
    return;
  }
  config->struct_size = sizeof(simple_torrent_config_t);
  config->max_torrents = 20;
  config->download_rate_limit = 0;
  config->upload_rate_limit = 0;
  config->connections_limit = 200;
  config->enable_dht = 1;
  config->user_agent = "simple_torrent/2.0.0";
}

simple_torrent_result_t simple_torrent_manager_create(
    const simple_torrent_config_t* config,
    simple_torrent_stats_callback_t stats_callback,
    simple_torrent_metadata_callback_t metadata_callback,
    void* user_data,
    simple_torrent_manager_t** manager_out) try {
  if (manager_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *manager_out = nullptr;
  NativeConfig native_config;
  if (const auto result = ConvertConfig(config, &native_config);
      result != SIMPLE_TORRENT_OK) {
    return result;
  }

  try {
    auto manager = std::make_unique<simple_torrent_manager_t>();
    manager->stats_callback = stats_callback;
    manager->metadata_callback = metadata_callback;
    manager->user_data = user_data;
    auto* manager_pointer = manager.get();
    manager->implementation = std::make_unique<NativeManager>(
        std::move(native_config),
        [manager_pointer](const auto& stats) {
          ForwardStats(manager_pointer, stats);
        },
        [manager_pointer](const auto& metadata) {
          ForwardMetadata(manager_pointer, metadata);
        });
    *manager_out = manager.release();
    return SIMPLE_TORRENT_OK;
  } catch (...) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

void simple_torrent_manager_destroy(simple_torrent_manager_t* manager) try {
  delete manager;
} catch (...) {
  // Destruction is best effort at the C ABI boundary.
}

simple_torrent_result_t simple_torrent_manager_update_config(
    simple_torrent_manager_t* manager,
    const simple_torrent_config_t* config) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || config == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  NativeConfig native_config;
  if (const auto result = ConvertConfig(config, &native_config);
      result != SIMPLE_TORRENT_OK) {
    return result;
  }
  return manager->implementation->UpdateConfig(native_config);
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_start(
    simple_torrent_manager_t* manager,
    const char* magnet,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || magnet == nullptr ||
      destination == nullptr || !IsUtf8(magnet) || !IsUtf8(destination) ||
      !IsOptionalUtf8(display_name)) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  return manager->implementation->Start(magnet, destination,
                                         OptionalString(display_name),
                                         torrent_id_out);
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_start_from_data(
    simple_torrent_manager_t* manager,
    const uint8_t* data,
    size_t data_size,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || destination == nullptr ||
      !IsUtf8(destination) || !IsOptionalUtf8(display_name)) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  return manager->implementation->StartFromData(
      data, data_size, destination, OptionalString(display_name),
      torrent_id_out);
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_start_from_file(
    simple_torrent_manager_t* manager,
    const char* torrent_file_path,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK ||
      torrent_file_path == nullptr || destination == nullptr ||
      !IsUtf8(torrent_file_path) || !IsUtf8(destination) ||
      !IsOptionalUtf8(display_name)) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  return manager->implementation->StartFromFile(
      torrent_file_path, destination, OptionalString(display_name),
      torrent_id_out);
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_set_transfers_suspended(
    simple_torrent_manager_t* manager, uint8_t suspended) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || suspended > 1) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  return manager->implementation->SetTransfersSuspended(suspended != 0);
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_transfers_suspended(
    simple_torrent_manager_t* manager, uint8_t* suspended_out) try {
  if (suspended_out != nullptr) {
    *suspended_out = 0;
  }
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || suspended_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  bool suspended = false;
  const auto result = manager->implementation->TransfersSuspended(&suspended);
  if (result == SIMPLE_TORRENT_OK) {
    *suspended_out = static_cast<uint8_t>(suspended);
  }
  return result;
} catch (...) {
  if (suspended_out != nullptr) {
    *suspended_out = 0;
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_pause(
    simple_torrent_manager_t* manager, int32_t torrent_id) try {
  return CheckManager(manager) == SIMPLE_TORRENT_OK
             ? manager->implementation->Pause(torrent_id)
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_resume(
    simple_torrent_manager_t* manager, int32_t torrent_id) try {
  return CheckManager(manager) == SIMPLE_TORRENT_OK
             ? manager->implementation->Resume(torrent_id)
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_cancel(
    simple_torrent_manager_t* manager, int32_t torrent_id) try {
  return CheckManager(manager) == SIMPLE_TORRENT_OK
             ? manager->implementation->Cancel(torrent_id)
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_finalise(
    simple_torrent_manager_t* manager, int32_t torrent_id) try {
  return CheckManager(manager) == SIMPLE_TORRENT_OK
             ? manager->implementation->Finalise(torrent_id)
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_active_ids(
    simple_torrent_manager_t* manager,
    int32_t** ids_out,
    size_t* count_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || ids_out == nullptr ||
      count_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *ids_out = nullptr;
  *count_out = 0;
  const auto ids = manager->implementation->ActiveIds();
  if (ids.empty()) {
    return SIMPLE_TORRENT_OK;
  }
  if (ids.size() > std::numeric_limits<std::size_t>::max() / sizeof(int32_t)) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
  auto* copy = static_cast<int32_t*>(
      std::malloc(ids.size() * sizeof(int32_t)));
  if (copy == nullptr) {
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
  std::memcpy(copy, ids.data(), ids.size() * sizeof(int32_t));
  *ids_out = copy;
  *count_out = ids.size();
  return SIMPLE_TORRENT_OK;
} catch (...) {
  if (ids_out != nullptr) {
    *ids_out = nullptr;
  }
  if (count_out != nullptr) {
    *count_out = 0;
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

void simple_torrent_active_ids_free(int32_t* ids) { std::free(ids); }

simple_torrent_result_t simple_torrent_manager_exists(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    uint8_t* exists_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || exists_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *exists_out = static_cast<uint8_t>(
      manager->implementation->Exists(torrent_id));
  return SIMPLE_TORRENT_OK;
} catch (...) {
  if (exists_out != nullptr) {
    *exists_out = 0;
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_state(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    simple_torrent_state_t* state_out) try {
  return CheckManager(manager) == SIMPLE_TORRENT_OK
             ? manager->implementation->State(torrent_id, state_out)
             : SIMPLE_TORRENT_INVALID_ARGUMENT;
} catch (...) {
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

simple_torrent_result_t simple_torrent_manager_torrent_info(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    simple_torrent_torrent_info_t* info_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || info_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *info_out = {};
  simple_torrent::native::TorrentInfo native_info;
  if (const auto result =
          manager->implementation->Info(torrent_id, &native_info);
      result != SIMPLE_TORRENT_OK) {
    return result;
  }

  info_out->id = native_info.id;
  info_out->magnet_uri = CopyString(native_info.magnet_uri);
  info_out->save_path = CopyString(native_info.save_path);
  info_out->display_name = CopyString(native_info.display_name);
  info_out->state = native_info.state;
  info_out->last_error = CopyString(native_info.last_error);
  info_out->created_at_milliseconds = native_info.created_at_milliseconds;
  if (info_out->magnet_uri == nullptr || info_out->save_path == nullptr ||
      info_out->display_name == nullptr || info_out->last_error == nullptr) {
    simple_torrent_torrent_info_free(info_out);
    return SIMPLE_TORRENT_NATIVE_ERROR;
  }
  return SIMPLE_TORRENT_OK;
} catch (...) {
  if (info_out != nullptr) {
    simple_torrent_torrent_info_free(info_out);
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

void simple_torrent_torrent_info_free(
    simple_torrent_torrent_info_t* info) {
  if (info == nullptr) {
    return;
  }
  std::free(info->magnet_uri);
  std::free(info->save_path);
  std::free(info->display_name);
  std::free(info->last_error);
  *info = {};
}

simple_torrent_result_t simple_torrent_manager_last_error(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    char** error_out) try {
  if (CheckManager(manager) != SIMPLE_TORRENT_OK || error_out == nullptr) {
    return SIMPLE_TORRENT_INVALID_ARGUMENT;
  }
  *error_out = nullptr;
  std::string error;
  if (const auto result =
          manager->implementation->LastError(torrent_id, &error);
      result != SIMPLE_TORRENT_OK) {
    return result;
  }
  *error_out = CopyString(error);
  return *error_out == nullptr ? SIMPLE_TORRENT_NATIVE_ERROR
                              : SIMPLE_TORRENT_OK;
} catch (...) {
  if (error_out != nullptr) {
    *error_out = nullptr;
  }
  return SIMPLE_TORRENT_NATIVE_ERROR;
}

void simple_torrent_string_free(char* value) { std::free(value); }

}  // extern "C"
