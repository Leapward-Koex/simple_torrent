#ifndef SIMPLE_TORRENT_NATIVE_H_
#define SIMPLE_TORRENT_NATIVE_H_

/*
 * Stable C ABI for the simple_torrent native runtime.
 *
 * All text is UTF-8. Input pointers are borrowed for the duration of a call.
 * Callback data (including nested strings and file arrays) is borrowed only for
 * the duration of the callback. Memory returned by query functions must be
 * released with the matching free function documented below.
 */

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(SIMPLE_TORRENT_NATIVE_BUILD)
#define STN_API __declspec(dllexport)
#else
#define STN_API __declspec(dllimport)
#endif
#else
#define STN_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define SIMPLE_TORRENT_NATIVE_ABI_VERSION 2u

typedef struct simple_torrent_manager simple_torrent_manager_t;

typedef enum simple_torrent_result {
  SIMPLE_TORRENT_OK = 0,
  SIMPLE_TORRENT_INVALID_ARGUMENT = 1,
  SIMPLE_TORRENT_NOT_FOUND = 2,
  SIMPLE_TORRENT_LIMIT_REACHED = 3,
  SIMPLE_TORRENT_INVALID_TORRENT = 4,
  SIMPLE_TORRENT_IO_ERROR = 5,
  SIMPLE_TORRENT_NATIVE_ERROR = 6,
  SIMPLE_TORRENT_DUPLICATE_TORRENT = 7
} simple_torrent_result_t;

typedef enum simple_torrent_state {
  SIMPLE_TORRENT_STATE_STARTING = 0,
  SIMPLE_TORRENT_STATE_DOWNLOADING_METADATA = 1,
  SIMPLE_TORRENT_STATE_DOWNLOADING = 2,
  SIMPLE_TORRENT_STATE_SEEDING = 3,
  SIMPLE_TORRENT_STATE_PAUSED = 4,
  SIMPLE_TORRENT_STATE_ERROR = 5,
  SIMPLE_TORRENT_STATE_STOPPED = 6
} simple_torrent_state_t;

typedef struct simple_torrent_config {
  /* Set to sizeof(simple_torrent_config_t). */
  size_t struct_size;
  int32_t max_torrents;
  int64_t download_rate_limit;
  int64_t upload_rate_limit;
  int32_t connections_limit;
  uint8_t enable_dht;
  const char* user_agent;
} simple_torrent_config_t;

typedef struct simple_torrent_stats {
  int32_t id;
  int64_t download_rate;
  int64_t upload_rate;
  int32_t pieces;
  int32_t pieces_total;
  double progress;
  int32_t seeds;
  int32_t peers;
  simple_torrent_state_t state;
} simple_torrent_stats_t;

typedef struct simple_torrent_file {
  int32_t index;
  const char* path;
  int64_t size;
  int64_t offset;
} simple_torrent_file_t;

typedef struct simple_torrent_metadata {
  int32_t id;
  const char* name;
  int64_t total_bytes;
  int32_t piece_size;
  int32_t piece_count;
  int32_t file_count;
  int64_t creation_date;
  uint8_t is_private;
  uint8_t is_v2;
  const char* v1_info_hash;
  const char* v2_info_hash;
  const simple_torrent_file_t* files;
  size_t files_count;
} simple_torrent_metadata_t;

/* Owned query result. Call simple_torrent_torrent_info_free exactly once. */
typedef struct simple_torrent_torrent_info {
  int32_t id;
  char* magnet_uri;
  char* save_path;
  char* display_name;
  simple_torrent_state_t state;
  char* last_error;
  int64_t created_at_milliseconds;
} simple_torrent_torrent_info_t;

typedef void (*simple_torrent_stats_callback_t)(
    void* user_data, const simple_torrent_stats_t* stats);
typedef void (*simple_torrent_metadata_callback_t)(
    void* user_data, const simple_torrent_metadata_t* metadata);

STN_API uint32_t simple_torrent_native_abi_version(void);
STN_API const char* simple_torrent_native_version(void);
/* Static, process-lifetime string containing embedded dependency versions. */
STN_API const char* simple_torrent_native_build_info(void);
/*
 * Returns borrowed process-lifetime PEM bytes embedded for Apple builds.
 * Returns NULL and writes zero on builds that use their OS trust store.
 */
STN_API const uint8_t* simple_torrent_embedded_ca_bundle(size_t* size_out);
STN_API const char* simple_torrent_state_name(simple_torrent_state_t state);
STN_API const char* simple_torrent_result_name(simple_torrent_result_t result);

STN_API void simple_torrent_config_init(simple_torrent_config_t* config);

/*
 * Creates a manager owned by the caller. Callbacks run on the manager's native
 * worker thread; platform adapters must marshal them to their platform thread.
 */
STN_API simple_torrent_result_t simple_torrent_manager_create(
    const simple_torrent_config_t* config,
    simple_torrent_stats_callback_t stats_callback,
    simple_torrent_metadata_callback_t metadata_callback,
    void* user_data,
    simple_torrent_manager_t** manager_out);

/*
 * Stops the worker and all callbacks before returning. Accepts NULL.
 * Do not destroy a manager or invoke lifecycle functions reentrantly from one
 * of its callbacks; marshal that work to the platform/application thread. The
 * caller must serialize lifecycle calls and ensure no manager call is in
 * flight before destroy begins.
 */
STN_API void simple_torrent_manager_destroy(simple_torrent_manager_t* manager);

STN_API simple_torrent_result_t simple_torrent_manager_update_config(
    simple_torrent_manager_t* manager,
    const simple_torrent_config_t* config);

STN_API simple_torrent_result_t simple_torrent_manager_start(
    simple_torrent_manager_t* manager,
    const char* magnet,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out);

STN_API simple_torrent_result_t simple_torrent_manager_start_from_data(
    simple_torrent_manager_t* manager,
    const uint8_t* data,
    size_t data_size,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out);

STN_API simple_torrent_result_t simple_torrent_manager_start_from_file(
    simple_torrent_manager_t* manager,
    const char* torrent_file_path,
    const char* destination,
    const char* display_name,
    int32_t* torrent_id_out);

/*
 * Suspends or resumes all network transfers in this manager's session.
 * This state is separate from each torrent's individual paused state.
 */
STN_API simple_torrent_result_t
simple_torrent_manager_set_transfers_suspended(
    simple_torrent_manager_t* manager, uint8_t suspended);
STN_API simple_torrent_result_t simple_torrent_manager_transfers_suspended(
    simple_torrent_manager_t* manager, uint8_t* suspended_out);

STN_API simple_torrent_result_t simple_torrent_manager_pause(
    simple_torrent_manager_t* manager, int32_t torrent_id);
STN_API simple_torrent_result_t simple_torrent_manager_resume(
    simple_torrent_manager_t* manager, int32_t torrent_id);
/* cancel removes the torrent and asks libtorrent to delete its payload. */
STN_API simple_torrent_result_t simple_torrent_manager_cancel(
    simple_torrent_manager_t* manager, int32_t torrent_id);
/* finalise removes the torrent while retaining all payload files. */
STN_API simple_torrent_result_t simple_torrent_manager_finalise(
    simple_torrent_manager_t* manager, int32_t torrent_id);

STN_API simple_torrent_result_t simple_torrent_manager_active_ids(
    simple_torrent_manager_t* manager,
    int32_t** ids_out,
    size_t* count_out);
/* Frees the array returned by simple_torrent_manager_active_ids. */
STN_API void simple_torrent_active_ids_free(int32_t* ids);

STN_API simple_torrent_result_t simple_torrent_manager_exists(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    uint8_t* exists_out);
STN_API simple_torrent_result_t simple_torrent_manager_state(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    simple_torrent_state_t* state_out);
STN_API simple_torrent_result_t simple_torrent_manager_torrent_info(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    simple_torrent_torrent_info_t* info_out);
STN_API void simple_torrent_torrent_info_free(
    simple_torrent_torrent_info_t* info);

/* Allocates a NUL-terminated UTF-8 string. Free it with simple_torrent_string_free. */
STN_API simple_torrent_result_t simple_torrent_manager_last_error(
    simple_torrent_manager_t* manager,
    int32_t torrent_id,
    char** error_out);
STN_API void simple_torrent_string_free(char* value);

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* SIMPLE_TORRENT_NATIVE_H_ */
