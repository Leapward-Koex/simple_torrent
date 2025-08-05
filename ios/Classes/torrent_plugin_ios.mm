#include "torrent_plugin_ios.hpp"
#include "../../shared/torrent_core/torrent_core.hpp"
#include <string>
#include <unordered_map>
#include <mutex>

// Include the implementation directly
#include "../../shared/torrent_core/torrent_core.cpp"

// Internal implementation
struct TorrentManager {
    std::unique_ptr<tc::Manager> manager;
    std::unordered_map<int, std::pair<StatsCallback, MetadataCallback>> callbacks;
    std::mutex callbackMutex;
    
    TorrentManager() {
        tc::ManagerConfig config;  // Use default config
        manager = std::make_unique<tc::Manager>(config);
    }
};

// Thread-safe callback handling
static void handleStats(TorrentManager* tmgr, int id, const tc::Stats& stats) {
    std::lock_guard<std::mutex> lock(tmgr->callbackMutex);
    auto it = tmgr->callbacks.find(id);
    if (it != tmgr->callbacks.end() && it->second.first) {
        std::string phase = stats.phase;
        std::string state;
        switch (stats.state) {
            case tc::TorrentState::Starting: state = "starting"; break;
            case tc::TorrentState::DownloadingMetadata: state = "downloadingMetadata"; break;
            case tc::TorrentState::Downloading: state = "downloading"; break;
            case tc::TorrentState::Seeding: state = "seeding"; break;
            case tc::TorrentState::Paused: state = "paused"; break;
            case tc::TorrentState::Error: state = "error"; break;
            case tc::TorrentState::Stopped: state = "stopped"; break;
            default: state = "unknown"; break;
        }
        
        it->second.first(stats.id, stats.dlRate, stats.ulRate, stats.pieces, 
                        stats.piecesTotal, stats.progress, stats.seeds, stats.peers,
                        phase.c_str(), state.c_str());
    }
}

static void handleMetadata(TorrentManager* tmgr, int id, const tc::Metadata& metadata) {
    std::lock_guard<std::mutex> lock(tmgr->callbackMutex);
    auto it = tmgr->callbacks.find(id);
    if (it != tmgr->callbacks.end() && it->second.second) {
        it->second.second(metadata.id, metadata.name.c_str(), metadata.totalBytes,
                         metadata.pieceSize, metadata.pieceCount, metadata.fileCount,
                         metadata.creationDate, metadata.isPrivate, metadata.isV2);
    }
}

extern "C" {

TorrentManager* torrent_manager_create() {
    return new TorrentManager();
}

void torrent_manager_destroy(TorrentManager* manager) {
    delete manager;
}

void torrent_manager_apply_config(TorrentManager* manager, int maxTorrents, int maxDownloadRate,
                                 int maxUploadRate, bool enableDHT, const char* userAgent) {
    if (!manager) return;
    
    tc::ManagerConfig config;
    config.maxTorrents = maxTorrents;
    config.maxDownloadRate = maxDownloadRate;
    config.maxUploadRate = maxUploadRate;
    config.enableDHT = enableDHT;
    config.userAgent = userAgent ? userAgent : "simple_torrent/1.0";
    
    manager->manager->applyConfig(config);
}

int torrent_manager_start(TorrentManager* manager, const char* magnet, const char* path,
                         const char* displayName, StatsCallback statsCallback,
                         MetadataCallback metadataCallback) {
    if (!manager || !magnet || !path) return 0;
    
    std::string displayStr = displayName ? displayName : "";
    
    int torrentId = manager->manager->start(
        magnet, path,
        [manager](const tc::Stats& stats) { handleStats(manager, stats.id, stats); },
        [manager](const tc::Metadata& metadata) { handleMetadata(manager, metadata.id, metadata); },
        displayStr
    );
    
    if (torrentId > 0) {
        std::lock_guard<std::mutex> lock(manager->callbackMutex);
        manager->callbacks[torrentId] = std::make_pair(statsCallback, metadataCallback);
    }
    
    return torrentId;
}

void torrent_manager_pause(TorrentManager* manager, int id) {
    if (manager) {
        manager->manager->pause(id);
    }
}

void torrent_manager_resume(TorrentManager* manager, int id) {
    if (manager) {
        manager->manager->resume(id);
    }
}

void torrent_manager_cancel(TorrentManager* manager, int id) {
    if (manager) {
        manager->manager->cancel(id);
        std::lock_guard<std::mutex> lock(manager->callbackMutex);
        manager->callbacks.erase(id);
    }
}

void torrent_manager_finalise(TorrentManager* manager, int id) {
    if (manager) {
        manager->manager->finalise(id);
        std::lock_guard<std::mutex> lock(manager->callbackMutex);
        manager->callbacks.erase(id);
    }
}

int* torrent_manager_get_active_ids(TorrentManager* manager, int* count) {
    if (!manager || !count) return nullptr;
    
    auto ids = manager->manager->getActiveTorrentIds();
    *count = static_cast<int>(ids.size());
    
    if (ids.empty()) return nullptr;
    
    int* result = new int[ids.size()];
    std::copy(ids.begin(), ids.end(), result);
    return result;
}

bool torrent_manager_exists(TorrentManager* manager, int id) {
    return manager ? manager->manager->exists(id) : false;
}

const char* torrent_manager_get_state(TorrentManager* manager, int id) {
    if (!manager) return nullptr;
    
    tc::TorrentState state = manager->manager->getState(id);
    static std::string stateStr;
    
    switch (state) {
        case tc::TorrentState::Starting: stateStr = "starting"; break;
        case tc::TorrentState::DownloadingMetadata: stateStr = "downloadingMetadata"; break;
        case tc::TorrentState::Downloading: stateStr = "downloading"; break;
        case tc::TorrentState::Seeding: stateStr = "seeding"; break;
        case tc::TorrentState::Paused: stateStr = "paused"; break;
        case tc::TorrentState::Error: stateStr = "error"; break;
        case tc::TorrentState::Stopped: stateStr = "stopped"; break;
        default: stateStr = "unknown"; break;
    }
    
    return stateStr.c_str();
}

const char* torrent_manager_get_last_error(TorrentManager* manager, int id) {
    if (!manager) return nullptr;
    
    static std::string errorStr = manager->manager->getLastError(id);
    return errorStr.c_str();
}

CTorrentInfo* torrent_manager_get_info(TorrentManager* manager, int id) {
    if (!manager) return nullptr;
    
    tc::TorrentInfo info = manager->manager->getTorrentInfo(id);
    
    CTorrentInfo* cInfo = new CTorrentInfo();
    cInfo->id = info.id;
    
    // Allocate and copy strings - these will need to be freed
    cInfo->magnetUri = strdup(info.magnetUri.c_str());
    cInfo->savePath = strdup(info.savePath.c_str());
    cInfo->displayName = strdup(info.displayName.c_str());
    cInfo->lastError = strdup(info.lastError.c_str());
    
    // Convert state to string
    std::string stateStr;
    switch (info.state) {
        case tc::TorrentState::Starting: stateStr = "starting"; break;
        case tc::TorrentState::DownloadingMetadata: stateStr = "downloadingMetadata"; break;
        case tc::TorrentState::Downloading: stateStr = "downloading"; break;
        case tc::TorrentState::Seeding: stateStr = "seeding"; break;
        case tc::TorrentState::Paused: stateStr = "paused"; break;
        case tc::TorrentState::Error: stateStr = "error"; break;
        case tc::TorrentState::Stopped: stateStr = "stopped"; break;
        default: stateStr = "unknown"; break;
    }
    cInfo->state = strdup(stateStr.c_str());
    
    // Convert time_point to unix timestamp
    auto duration = info.createdAt.time_since_epoch();
    cInfo->createdAt = std::chrono::duration_cast<std::chrono::seconds>(duration).count();
    
    return cInfo;
}

void torrent_manager_free_torrent_info(CTorrentInfo* info) {
    if (!info) return;
    
    free(const_cast<char*>(info->magnetUri));
    free(const_cast<char*>(info->savePath));
    free(const_cast<char*>(info->displayName));
    free(const_cast<char*>(info->state));
    free(const_cast<char*>(info->lastError));
    delete info;
}

void torrent_manager_free_string(const char* str) {
    // In this implementation, strings are managed by static storage
    // No need to free anything
}

void torrent_manager_free_int_array(int* array) {
    delete[] array;
}

} // extern "C"
