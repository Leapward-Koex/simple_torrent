#include "simple_torrent_plugin.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <limits>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace simple_torrent_windows {
namespace {

constexpr char kMethodsChannel[] = "simple_torrent/methods";
constexpr char kProgressChannel[] = "simple_torrent/progress";
constexpr char kMetadataChannel[] = "simple_torrent/metadata";
constexpr UINT kNativeEventMessage = WM_APP + 0x4f2;
constexpr std::size_t kMaxBufferedEvents = 10;

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableMap* Arguments(
    const flutter::MethodCall<EncodableValue>& call) {
  return std::get_if<EncodableMap>(call.arguments());
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto iterator = map.find(EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

const std::string* ReadString(const EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  return value == nullptr ? nullptr : std::get_if<std::string>(value);
}

bool HasEmbeddedNull(const std::string& value) {
  return value.find('\0') != std::string::npos;
}

bool ReadOptionalString(const EncodableMap& map,
                        const char* key,
                        const std::string** output) {
  const auto* value = Find(map, key);
  if (value == nullptr || std::holds_alternative<std::monostate>(*value)) {
    *output = nullptr;
    return true;
  }
  const auto* string = std::get_if<std::string>(value);
  if (string == nullptr || HasEmbeddedNull(*string)) {
    return false;
  }
  *output = string;
  return true;
}

bool ReadInt64(const EncodableMap& map,
               const char* key,
               std::int64_t* output) {
  const auto* value = Find(map, key);
  if (value == nullptr) {
    return false;
  }
  if (const auto* number = std::get_if<std::int32_t>(value)) {
    *output = *number;
    return true;
  }
  if (const auto* number = std::get_if<std::int64_t>(value)) {
    *output = *number;
    return true;
  }
  return false;
}

bool ReadId(const EncodableMap* arguments, std::int32_t* id) {
  std::int64_t value = 0;
  if (arguments == nullptr || !ReadInt64(*arguments, "id", &value) ||
      value <= 0 || value > std::numeric_limits<std::int32_t>::max()) {
    return false;
  }
  *id = static_cast<std::int32_t>(value);
  return true;
}

const char* ErrorCode(simple_torrent_result_t code,
                      const char* invalid_code = "invalid_argument") {
  switch (code) {
    case SIMPLE_TORRENT_INVALID_ARGUMENT:
    case SIMPLE_TORRENT_INVALID_TORRENT:
      return invalid_code;
    case SIMPLE_TORRENT_NOT_FOUND:
      return "torrent_not_found";
    case SIMPLE_TORRENT_LIMIT_REACHED:
      return "torrent_limit_reached";
    case SIMPLE_TORRENT_IO_ERROR:
      return "io_error";
    case SIMPLE_TORRENT_DUPLICATE_TORRENT:
      return "duplicate_torrent";
    case SIMPLE_TORRENT_NATIVE_ERROR:
    default:
      return "native_error";
  }
}

void Complete(simple_torrent_result_t code,
              flutter::MethodResult<EncodableValue>* result,
              const char* invalid_code = "invalid_argument") {
  if (code == SIMPLE_TORRENT_OK) {
    result->Success(EncodableValue());
    return;
  }
  result->Error(ErrorCode(code, invalid_code),
                std::string("Native operation failed: ") +
                    simple_torrent_result_name(code));
}

void Invalid(flutter::MethodResult<EncodableValue>* result,
             const char* message) {
  result->Error("invalid_argument", message);
}

simple_torrent_result_t ConfigFromMap(const EncodableMap& map,
                                      simple_torrent_config_t* config,
                                      std::string* user_agent) {
  simple_torrent_config_init(config);
  *user_agent = config->user_agent;
  std::int64_t number = 0;

  if (Find(map, "maxTorrents") != nullptr) {
    if (!ReadInt64(map, "maxTorrents", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    if (number < std::numeric_limits<std::int32_t>::min() ||
        number > std::numeric_limits<std::int32_t>::max()) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->max_torrents = static_cast<std::int32_t>(number);
  }
  if (Find(map, "downloadRateLimit") != nullptr) {
    if (!ReadInt64(map, "downloadRateLimit", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->download_rate_limit = number;
  }
  if (Find(map, "uploadRateLimit") != nullptr) {
    if (!ReadInt64(map, "uploadRateLimit", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->upload_rate_limit = number;
  }
  if (Find(map, "connectionsLimit") != nullptr) {
    if (!ReadInt64(map, "connectionsLimit", &number)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    if (number < std::numeric_limits<std::int32_t>::min() ||
        number > std::numeric_limits<std::int32_t>::max()) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    config->connections_limit = static_cast<std::int32_t>(number);
  }
  if (const auto* value = Find(map, "enableDht")) {
    if (const auto* enabled = std::get_if<bool>(value)) {
      config->enable_dht = static_cast<std::uint8_t>(*enabled);
    } else {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
  }
  if (Find(map, "userAgent") != nullptr) {
    const auto* value = ReadString(map, "userAgent");
    if (value == nullptr || HasEmbeddedNull(*value)) {
      return SIMPLE_TORRENT_INVALID_ARGUMENT;
    }
    *user_agent = *value;
  }
  config->user_agent = user_agent->c_str();
  return SIMPLE_TORRENT_OK;
}

}  // namespace

struct SimpleTorrentPlugin::NativeState
    : std::enable_shared_from_this<SimpleTorrentPlugin::NativeState> {
  struct FinaliseTask {
    std::uint64_t request_id;
    std::int32_t torrent_id;
  };

  explicit NativeState(SimpleTorrentPlugin* plugin) : plugin_(plugin) {}

  void SetManager(simple_torrent_manager_t* manager) {
    manager_.store(manager, std::memory_order_release);
  }

  simple_torrent_manager_t* GetManager() const {
    return manager_.load(std::memory_order_acquire);
  }

  bool StartWorker() {
    auto state = shared_from_this();
    {
      std::lock_guard lock(task_mutex_);
      if (worker_started_) {
        return false;
      }
      worker_started_ = true;
    }
    try {
      std::thread worker([state = std::move(state)] { state->Run(); });
      try {
        worker.detach();
      } catch (...) {
        {
          std::lock_guard lock(task_mutex_);
          shutdown_requested_ = true;
        }
        task_condition_.notify_one();
        worker.join();
        return false;
      }
    } catch (...) {
      std::lock_guard lock(task_mutex_);
      worker_started_ = false;
      return false;
    }
    return true;
  }

  bool EnqueueFinalise(std::uint64_t request_id, std::int32_t torrent_id) {
    {
      std::lock_guard lock(task_mutex_);
      if (!worker_started_ || shutdown_requested_) {
        return false;
      }
      finalise_tasks_.push_back(FinaliseTask{request_id, torrent_id});
    }
    task_condition_.notify_one();
    return true;
  }

  void InvalidatePlugin() {
    std::lock_guard lock(callback_mutex_);
    plugin_ = nullptr;
  }

  void Shutdown() {
    {
      std::lock_guard lock(task_mutex_);
      if (!worker_started_) {
        return;
      }
      shutdown_requested_ = true;
    }
    task_condition_.notify_one();
  }

  void DispatchEvent(PendingEvent event) {
    std::lock_guard lock(callback_mutex_);
    if (plugin_ != nullptr) {
      plugin_->QueueEvent(std::move(event));
    }
  }

  void DispatchFinaliseCompletion(std::uint64_t request_id,
                                  simple_torrent_result_t code) {
    std::lock_guard lock(callback_mutex_);
    if (plugin_ != nullptr) {
      plugin_->QueueFinaliseCompletion(request_id, code);
    }
  }

  void DestroyManager() {
    auto* manager = manager_.exchange(nullptr, std::memory_order_acq_rel);
    if (manager != nullptr) {
      simple_torrent_manager_destroy(manager);
    }
  }

 private:
  void Run() {
    while (true) {
      FinaliseTask task{};
      {
        std::unique_lock lock(task_mutex_);
        task_condition_.wait(lock, [this] {
          return shutdown_requested_ || !finalise_tasks_.empty();
        });
        if (finalise_tasks_.empty()) {
          if (shutdown_requested_) {
            break;
          }
          continue;
        }
        task = finalise_tasks_.front();
        finalise_tasks_.pop_front();
      }

      simple_torrent_result_t code = SIMPLE_TORRENT_NATIVE_ERROR;
      try {
        code = simple_torrent_manager_finalise(GetManager(), task.torrent_id);
      } catch (...) {
        code = SIMPLE_TORRENT_NATIVE_ERROR;
      }
      DispatchFinaliseCompletion(task.request_id, code);
    }

    DestroyManager();
    std::lock_guard lock(task_mutex_);
    worker_started_ = false;
  }

  std::atomic<simple_torrent_manager_t*> manager_{nullptr};
  std::mutex callback_mutex_;
  SimpleTorrentPlugin* plugin_ = nullptr;
  std::mutex task_mutex_;
  std::condition_variable task_condition_;
  std::deque<FinaliseTask> finalise_tasks_;
  bool worker_started_ = false;
  bool shutdown_requested_ = false;
};

void SimpleTorrentPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), kMethodsChannel,
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<SimpleTorrentPlugin>(registrar);
  method_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

SimpleTorrentPlugin::SimpleTorrentPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  if (registrar_->GetView() != nullptr) {
    view_window_ = registrar_->GetView()->GetNativeWindow();
  }
  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(window, message, wparam, lparam);
      });

  auto progress_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kProgressChannel,
          &flutter::StandardMethodCodec::GetInstance());
  progress_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) {
            stats_sink_ = std::move(sink);
            while (!stats_buffer_.empty()) {
              stats_sink_->Success(stats_buffer_.front());
              stats_buffer_.pop_front();
            }
            return nullptr;
          },
          [this](const EncodableValue*) {
            stats_sink_.reset();
            return nullptr;
          }));

  auto metadata_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar_->messenger(), kMetadataChannel,
          &flutter::StandardMethodCodec::GetInstance());
  metadata_channel->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink) {
            metadata_sink_ = std::move(sink);
            while (!metadata_buffer_.empty()) {
              metadata_sink_->Success(metadata_buffer_.begin()->second);
              metadata_buffer_.erase(metadata_buffer_.begin());
            }
            return nullptr;
          },
          [this](const EncodableValue*) {
            metadata_sink_.reset();
            return nullptr;
          }));

  simple_torrent_config_t config;
  simple_torrent_config_init(&config);
  native_state_ = std::make_shared<NativeState>(this);
  simple_torrent_manager_t* manager = nullptr;
  const auto create_result =
      simple_torrent_native_abi_version() == SIMPLE_TORRENT_NATIVE_ABI_VERSION
          ? simple_torrent_manager_create(&config, OnStats, OnMetadata,
                                          native_state_.get(), &manager)
          : SIMPLE_TORRENT_NATIVE_ERROR;
  native_state_->SetManager(manager);
  if (create_result != SIMPLE_TORRENT_OK || manager == nullptr ||
      !native_state_->StartWorker()) {
    native_state_->InvalidatePlugin();
    native_state_->DestroyManager();
    native_state_.reset();
  }
}

SimpleTorrentPlugin::~SimpleTorrentPlugin() {
  auto native_state = std::move(native_state_);
  if (native_state != nullptr) {
    // Invalidation waits only for a callback currently copying its event into
    // this plugin. Once it returns, native code can no longer dereference us.
    native_state->InvalidatePlugin();
  }
  CancelPendingFinaliseResults();
  if (native_state != nullptr) {
    // The detached worker owns native_state until all accepted finalise calls
    // finish and it destroys the manager exactly once.
    native_state->Shutdown();
  }
  if (window_proc_delegate_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
  std::lock_guard lock(pending_mutex_);
  pending_events_.clear();
  pending_finalise_completions_.clear();
}

void SimpleTorrentPlugin::OnStats(void* user_data,
                                  const simple_torrent_stats_t* stats) {
  if (user_data == nullptr || stats == nullptr) {
    return;
  }
  EncodableMap map;
  map[EncodableValue("eventType")] = EncodableValue("stats");
  map[EncodableValue("id")] = EncodableValue(stats->id);
  map[EncodableValue("download_rate")] =
      EncodableValue(stats->download_rate);
  map[EncodableValue("upload_rate")] = EncodableValue(stats->upload_rate);
  map[EncodableValue("pieces")] = EncodableValue(stats->pieces);
  map[EncodableValue("pieces_total")] = EncodableValue(stats->pieces_total);
  map[EncodableValue("progress")] = EncodableValue(stats->progress);
  map[EncodableValue("seeds")] = EncodableValue(stats->seeds);
  map[EncodableValue("peers")] = EncodableValue(stats->peers);
  map[EncodableValue("state")] =
      EncodableValue(simple_torrent_state_name(stats->state));
  static_cast<NativeState*>(user_data)->DispatchEvent(
      PendingEvent{EventKind::kStats, stats->id,
                   EncodableValue(std::move(map))});
}

void SimpleTorrentPlugin::OnMetadata(
    void* user_data, const simple_torrent_metadata_t* metadata) {
  if (user_data == nullptr || metadata == nullptr) {
    return;
  }
  EncodableMap map;
  map[EncodableValue("eventType")] = EncodableValue("metadata");
  map[EncodableValue("id")] = EncodableValue(metadata->id);
  map[EncodableValue("name")] = EncodableValue(metadata->name);
  map[EncodableValue("total_bytes")] = EncodableValue(metadata->total_bytes);
  map[EncodableValue("piece_size")] = EncodableValue(metadata->piece_size);
  map[EncodableValue("piece_count")] = EncodableValue(metadata->piece_count);
  map[EncodableValue("file_count")] = EncodableValue(metadata->file_count);
  map[EncodableValue("creation_date")] =
      EncodableValue(metadata->creation_date);
  map[EncodableValue("private")] =
      EncodableValue(metadata->is_private != 0);
  map[EncodableValue("v2")] = EncodableValue(metadata->is_v2 != 0);
  map[EncodableValue("v1_info_hash")] =
      EncodableValue(metadata->v1_info_hash);
  map[EncodableValue("v2_info_hash")] =
      EncodableValue(metadata->v2_info_hash);

  EncodableList files;
  files.reserve(metadata->files_count);
  for (std::size_t index = 0; index < metadata->files_count; ++index) {
    const auto& file = metadata->files[index];
    EncodableMap file_map;
    file_map[EncodableValue("index")] = EncodableValue(file.index);
    file_map[EncodableValue("path")] = EncodableValue(file.path);
    file_map[EncodableValue("size")] = EncodableValue(file.size);
    file_map[EncodableValue("offset")] = EncodableValue(file.offset);
    files.emplace_back(std::move(file_map));
  }
  map[EncodableValue("files")] = EncodableValue(std::move(files));
  static_cast<NativeState*>(user_data)->DispatchEvent(
      PendingEvent{EventKind::kMetadata, metadata->id,
                   EncodableValue(std::move(map))});
}

void SimpleTorrentPlugin::QueueEvent(PendingEvent event) {
  {
    std::lock_guard lock(pending_mutex_);
    pending_events_.push_back(std::move(event));
  }
  PostPlatformMessage();
}

void SimpleTorrentPlugin::QueueFinalise(
    std::int32_t torrent_id,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto native_state = native_state_;
  if (native_state == nullptr) {
    result->Error("not_initialized", "Native manager is not available");
    return;
  }
  std::uint64_t request_id = 0;
  do {
    request_id = next_finalise_request_id_++;
    if (next_finalise_request_id_ == 0) {
      next_finalise_request_id_ = 1;
    }
  } while (request_id == 0 ||
           finalise_results_.find(request_id) != finalise_results_.end());
  finalise_results_.emplace(request_id, std::move(result));
  if (!native_state->EnqueueFinalise(request_id, torrent_id)) {
    auto iterator = finalise_results_.find(request_id);
    auto rejected_result = std::move(iterator->second);
    finalise_results_.erase(iterator);
    rejected_result->Error("not_initialized",
                           "Native manager is not available");
  }
}

void SimpleTorrentPlugin::QueueFinaliseCompletion(
    std::uint64_t request_id, simple_torrent_result_t code) {
  {
    std::lock_guard lock(pending_mutex_);
    pending_finalise_completions_.push_back(
        FinaliseCompletion{request_id, code});
  }
  PostPlatformMessage();
}

void SimpleTorrentPlugin::DrainFinaliseCompletions() {
  std::deque<FinaliseCompletion> completions;
  {
    std::lock_guard lock(pending_mutex_);
    completions.swap(pending_finalise_completions_);
  }
  while (!completions.empty()) {
    const auto completion = completions.front();
    completions.pop_front();
    const auto iterator = finalise_results_.find(completion.request_id);
    if (iterator == finalise_results_.end()) {
      continue;
    }
    auto result = std::move(iterator->second);
    finalise_results_.erase(iterator);
    Complete(completion.code, result.get());
  }
}

void SimpleTorrentPlugin::CancelPendingFinaliseResults() {
  {
    std::lock_guard lock(pending_mutex_);
    pending_finalise_completions_.clear();
  }
  for (auto& item : finalise_results_) {
    item.second->Error("not_initialized",
                       "Native manager is no longer available");
  }
  finalise_results_.clear();
}

void SimpleTorrentPlugin::PostPlatformMessage() {
  if (view_window_ != nullptr) {
    // The standard runner calls RegisterPlugins before SetChildContent, so the
    // view may not have a parent in our constructor. Resolve its current root
    // here, after the runner has established the final window hierarchy.
    const auto root_window = GetAncestor(view_window_, GA_ROOT);
    const auto event_window =
        root_window == nullptr ? view_window_ : root_window;
    PostMessage(event_window, kNativeEventMessage,
                reinterpret_cast<WPARAM>(this), 0);
  }
}

std::optional<LRESULT> SimpleTorrentPlugin::HandleWindowMessage(
    HWND,
    UINT message,
    WPARAM wparam,
    LPARAM) {
  if (message != kNativeEventMessage ||
      wparam != reinterpret_cast<WPARAM>(this)) {
    return std::nullopt;
  }
  DrainEvents();
  DrainFinaliseCompletions();
  return 0;
}

void SimpleTorrentPlugin::DrainEvents() {
  std::deque<PendingEvent> events;
  {
    std::lock_guard lock(pending_mutex_);
    events.swap(pending_events_);
  }
  while (!events.empty()) {
    EmitOrBuffer(std::move(events.front()));
    events.pop_front();
  }
}

void SimpleTorrentPlugin::EmitOrBuffer(PendingEvent event) {
  auto* sink = event.kind == EventKind::kStats ? stats_sink_.get()
                                                : metadata_sink_.get();
  if (sink != nullptr) {
    sink->Success(event.value);
    return;
  }
  if (event.kind == EventKind::kMetadata) {
    metadata_buffer_.insert_or_assign(event.torrent_id,
                                      std::move(event.value));
    return;
  }
  stats_buffer_.push_back(std::move(event.value));
  while (stats_buffer_.size() > kMaxBufferedEvents) {
    stats_buffer_.pop_front();
  }
}

void SimpleTorrentPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto native_state = native_state_;
  auto* manager =
      native_state == nullptr ? nullptr : native_state->GetManager();
  if (manager == nullptr) {
    result->Error("not_initialized", "Native manager is not available");
    return;
  }

  const auto& method = method_call.method_name();
  const auto* arguments = Arguments(method_call);

  if (method == "init" || method == "updateConfig") {
    if (method_call.arguments() != nullptr && arguments == nullptr &&
        !std::holds_alternative<std::monostate>(*method_call.arguments())) {
      Complete(SIMPLE_TORRENT_INVALID_ARGUMENT, result.get(),
               "invalid_config");
      return;
    }
    const EncodableMap* config_map = nullptr;
    if (arguments != nullptr) {
      const auto* config = Find(*arguments, "config");
      if (config != nullptr) {
        config_map = std::get_if<EncodableMap>(config);
        if (config_map == nullptr) {
          Complete(SIMPLE_TORRENT_INVALID_ARGUMENT, result.get(),
                   "invalid_config");
          return;
        }
      }
    }
    if (config_map == nullptr) {
      if (method == "init") {
        result->Success(EncodableValue());
      } else {
        result->Error("invalid_config", "config is required");
      }
      return;
    }
    simple_torrent_config_t config;
    std::string user_agent;
    const auto conversion = ConfigFromMap(*config_map, &config, &user_agent);
    if (conversion != SIMPLE_TORRENT_OK) {
      Complete(conversion, result.get(), "invalid_config");
      return;
    }
    Complete(simple_torrent_manager_update_config(manager, &config),
             result.get(), "invalid_config");
    return;
  }

  if (method == "start") {
    if (arguments == nullptr) {
      Invalid(result.get(), "arguments are required");
      return;
    }
    const auto* magnet = ReadString(*arguments, "magnet");
    const auto* destination = ReadString(*arguments, "destination");
    if (magnet == nullptr || magnet->empty() || destination == nullptr ||
        destination->empty() || HasEmbeddedNull(*magnet) ||
        HasEmbeddedNull(*destination)) {
      Invalid(result.get(), "magnet and destination are required");
      return;
    }
    const std::string* display_name = nullptr;
    if (!ReadOptionalString(*arguments, "displayName", &display_name)) {
      Invalid(result.get(), "displayName must be a string without NUL bytes");
      return;
    }
    std::int32_t id = 0;
    const auto code = simple_torrent_manager_start(
        manager, magnet->c_str(), destination->c_str(),
        display_name == nullptr ? nullptr : display_name->c_str(), &id);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(id));
    } else {
      Complete(code, result.get(), "invalid_magnet");
    }
    return;
  }

  if (method == "startFromData") {
    if (arguments == nullptr) {
      Invalid(result.get(), "arguments are required");
      return;
    }
    const auto* data_value = Find(*arguments, "data");
    const auto* data = data_value == nullptr
                           ? nullptr
                           : std::get_if<std::vector<std::uint8_t>>(data_value);
    const auto* destination = ReadString(*arguments, "destination");
    if (data == nullptr || data->empty() || destination == nullptr ||
        destination->empty() || HasEmbeddedNull(*destination)) {
      Invalid(result.get(), "data and destination are required");
      return;
    }
    const std::string* display_name = nullptr;
    if (!ReadOptionalString(*arguments, "displayName", &display_name)) {
      Invalid(result.get(), "displayName must be a string without NUL bytes");
      return;
    }
    std::int32_t id = 0;
    const auto code = simple_torrent_manager_start_from_data(
        manager, data->data(), data->size(), destination->c_str(),
        display_name == nullptr ? nullptr : display_name->c_str(), &id);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(id));
    } else {
      Complete(code, result.get(), "invalid_torrent_data");
    }
    return;
  }

  if (method == "startFromFile") {
    if (arguments == nullptr) {
      Invalid(result.get(), "arguments are required");
      return;
    }
    const auto* torrent_file_path = ReadString(*arguments, "torrentFilePath");
    const auto* destination = ReadString(*arguments, "destination");
    if (torrent_file_path == nullptr || torrent_file_path->empty() ||
        destination == nullptr || destination->empty() ||
        HasEmbeddedNull(*torrent_file_path) ||
        HasEmbeddedNull(*destination)) {
      Invalid(result.get(), "torrentFilePath and destination are required");
      return;
    }
    const std::string* display_name = nullptr;
    if (!ReadOptionalString(*arguments, "displayName", &display_name)) {
      Invalid(result.get(), "displayName must be a string without NUL bytes");
      return;
    }
    std::int32_t id = 0;
    const auto code = simple_torrent_manager_start_from_file(
        manager, torrent_file_path->c_str(), destination->c_str(),
        display_name == nullptr ? nullptr : display_name->c_str(), &id);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(id));
    } else {
      Complete(code, result.get(), "invalid_torrent_file");
    }
    return;
  }

  if (method == "setTransfersSuspended") {
    if (arguments == nullptr) {
      Invalid(result.get(), "suspended must be a boolean");
      return;
    }
    const auto* value = Find(*arguments, "suspended");
    const auto* suspended =
        value == nullptr ? nullptr : std::get_if<bool>(value);
    if (suspended == nullptr) {
      Invalid(result.get(), "suspended must be a boolean");
      return;
    }
    Complete(simple_torrent_manager_set_transfers_suspended(
                 manager, static_cast<std::uint8_t>(*suspended)),
             result.get());
    return;
  }

  if (method == "areTransfersSuspended") {
    std::uint8_t suspended = 0;
    const auto code =
        simple_torrent_manager_transfers_suspended(manager, &suspended);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(suspended != 0));
    } else {
      Complete(code, result.get());
    }
    return;
  }

  if (method == "getActiveTorrentIds") {
    std::int32_t* ids = nullptr;
    std::size_t count = 0;
    const auto code = simple_torrent_manager_active_ids(manager, &ids, &count);
    if (code != SIMPLE_TORRENT_OK) {
      Complete(code, result.get());
      return;
    }
    EncodableList list;
    list.reserve(count);
    for (std::size_t index = 0; index < count; ++index) {
      list.emplace_back(ids[index]);
    }
    simple_torrent_active_ids_free(ids);
    result->Success(EncodableValue(std::move(list)));
    return;
  }

  std::int32_t id = 0;
  if ((method == "pause" || method == "resume" || method == "cancel" ||
       method == "finalise" || method == "exists" || method == "getState" ||
       method == "getTorrentInfo" || method == "getLastError") &&
      !ReadId(arguments, &id)) {
    Invalid(result.get(), "id must be a positive integer");
    return;
  }

  if (method == "pause") {
    Complete(simple_torrent_manager_pause(manager, id), result.get());
  } else if (method == "resume") {
    Complete(simple_torrent_manager_resume(manager, id), result.get());
  } else if (method == "cancel") {
    Complete(simple_torrent_manager_cancel(manager, id), result.get());
  } else if (method == "finalise") {
    QueueFinalise(id, std::move(result));
  } else if (method == "exists") {
    std::uint8_t exists = 0;
    const auto code = simple_torrent_manager_exists(manager, id, &exists);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(exists != 0));
    } else {
      Complete(code, result.get());
    }
  } else if (method == "getState") {
    simple_torrent_state_t state;
    const auto code = simple_torrent_manager_state(manager, id, &state);
    if (code == SIMPLE_TORRENT_OK) {
      result->Success(EncodableValue(simple_torrent_state_name(state)));
    } else {
      Complete(code, result.get());
    }
  } else if (method == "getTorrentInfo") {
    simple_torrent_torrent_info_t info{};
    const auto code = simple_torrent_manager_torrent_info(manager, id, &info);
    if (code != SIMPLE_TORRENT_OK) {
      Complete(code, result.get());
      return;
    }
    EncodableMap map;
    map[EncodableValue("id")] = EncodableValue(info.id);
    map[EncodableValue("magnetUri")] = EncodableValue(info.magnet_uri);
    map[EncodableValue("savePath")] = EncodableValue(info.save_path);
    map[EncodableValue("displayName")] = EncodableValue(info.display_name);
    map[EncodableValue("state")] =
        EncodableValue(simple_torrent_state_name(info.state));
    map[EncodableValue("lastError")] = EncodableValue(info.last_error);
    map[EncodableValue("createdAt")] =
        EncodableValue(info.created_at_milliseconds);
    simple_torrent_torrent_info_free(&info);
    result->Success(EncodableValue(std::move(map)));
  } else if (method == "getLastError") {
    char* error = nullptr;
    const auto code = simple_torrent_manager_last_error(manager, id, &error);
    if (code == SIMPLE_TORRENT_OK) {
      const std::string value(error == nullptr ? "" : error);
      simple_torrent_string_free(error);
      result->Success(EncodableValue(value));
    } else {
      Complete(code, result.get());
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace simple_torrent_windows
