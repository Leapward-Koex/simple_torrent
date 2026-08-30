#ifndef FLUTTER_PLUGIN_SIMPLE_TORRENT_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SIMPLE_TORRENT_WINDOWS_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_sink.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>
#include <flutter/plugin_registrar_windows.h>

#include <windows.h>

#include <cstdint>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <optional>

#include "simple_torrent_native.h"

namespace simple_torrent_windows {

class SimpleTorrentPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  explicit SimpleTorrentPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~SimpleTorrentPlugin() override;

  SimpleTorrentPlugin(const SimpleTorrentPlugin&) = delete;
  SimpleTorrentPlugin& operator=(const SimpleTorrentPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  enum class EventKind { kStats, kMetadata };
  struct PendingEvent {
    EventKind kind;
    std::int32_t torrent_id;
    flutter::EncodableValue value;
  };
  struct FinaliseCompletion {
    std::uint64_t request_id;
    simple_torrent_result_t code;
  };
  struct NativeState;

  static void OnStats(void* user_data,
                      const simple_torrent_stats_t* stats);
  static void OnMetadata(void* user_data,
                         const simple_torrent_metadata_t* metadata);

  void QueueEvent(PendingEvent event);
  void QueueFinalise(
      std::int32_t torrent_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void QueueFinaliseCompletion(std::uint64_t request_id,
                               simple_torrent_result_t code);
  void DrainFinaliseCompletions();
  void CancelPendingFinaliseResults();
  void PostPlatformMessage();
  void DrainEvents();
  void EmitOrBuffer(PendingEvent event);
  std::optional<LRESULT> HandleWindowMessage(HWND window,
                                              UINT message,
                                              WPARAM wparam,
                                              LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_;
  // The runner registers plugins before it reparents this Flutter view HWND.
  // QueueEvent resolves its current root at callback time so the message is
  // delivered to RegisterTopLevelWindowProcDelegate after that reparenting.
  HWND view_window_ = nullptr;
  int window_proc_delegate_id_ = -1;
  std::shared_ptr<NativeState> native_state_;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> stats_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> metadata_sink_;
  std::deque<flutter::EncodableValue> stats_buffer_;
  std::map<std::int32_t, flutter::EncodableValue> metadata_buffer_;
  std::mutex pending_mutex_;
  std::deque<PendingEvent> pending_events_;
  std::deque<FinaliseCompletion> pending_finalise_completions_;
  std::map<
      std::uint64_t,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      finalise_results_;
  std::uint64_t next_finalise_request_id_ = 1;
};

}  // namespace simple_torrent_windows

#endif  // FLUTTER_PLUGIN_SIMPLE_TORRENT_WINDOWS_PLUGIN_H_
