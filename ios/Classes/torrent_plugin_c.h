#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TorrentManager TorrentManager;

typedef void (*StatsCallback)(int id, int dlRate, int ulRate, int pieces, int piecesTotal,
                              int progressPct, int seeds, int peers, const char *phase, const char *state);
typedef void (*MetadataCallback)(int id, const char *name, long long totalBytes, int pieceSize,
                                 int pieceCount, int fileCount, long long creationDate,
                                 bool isPrivate, bool isV2);

TorrentManager *torrent_manager_create();
void torrent_manager_destroy(TorrentManager *manager);

void torrent_manager_apply_config(TorrentManager *manager, int maxTorrents, int maxDownloadRate,
                                  int maxUploadRate, bool enableDHT, const char *userAgent);

int torrent_manager_start(TorrentManager *manager, const char *magnet, const char *path,
                          const char *displayName, StatsCallback statsCallback,
                          MetadataCallback metadataCallback);
void torrent_manager_pause(TorrentManager *manager, int id);
void torrent_manager_resume(TorrentManager *manager, int id);
void torrent_manager_cancel(TorrentManager *manager, int id);

int *torrent_manager_get_active_ids(TorrentManager *manager, int *count);
bool torrent_manager_exists(TorrentManager *manager, int id);
const char *torrent_manager_get_state(TorrentManager *manager, int id);
const char *torrent_manager_get_last_error(TorrentManager *manager, int id);

typedef struct {
    int id;
    const char *magnetUri;
    const char *savePath;
    const char *displayName;
    const char *state;
    const char *lastError;
    long long createdAt;
} CTorrentInfo;

CTorrentInfo *torrent_manager_get_info(TorrentManager *manager, int id);
void torrent_manager_free_torrent_info(CTorrentInfo *info);

void torrent_manager_free_string(const char *str);
void torrent_manager_free_int_array(int *array);

#ifdef __cplusplus
} // extern "C"
#endif
