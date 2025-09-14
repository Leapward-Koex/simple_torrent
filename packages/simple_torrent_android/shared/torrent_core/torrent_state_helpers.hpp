// torrent_state_helpers.hpp  ───────────────────────────────────────────
#pragma once
#include "torrent_core.hpp"
#include <string_view>
#include <array>

namespace tc
{
    // Constexpr string helpers for TorrentState enum
    constexpr std::string_view stateToStringView(TorrentState state) noexcept
    {
        switch (state)
        {
        case TorrentState::Starting: return "starting";
        case TorrentState::DownloadingMetadata: return "downloadingMetadata";
        case TorrentState::Downloading: return "downloading";
        case TorrentState::Seeding: return "seeding";
        case TorrentState::Paused: return "paused";
        case TorrentState::Error: return "error";
        case TorrentState::Stopped: return "stopped";
        default: return "unknown";
        }
    }

    // Helper for C-style strings (for platform wrappers)
    constexpr const char* stateToString(TorrentState state) noexcept
    {
        return stateToStringView(state).data();
    }

    // Array of all state strings for iteration/validation
    constexpr std::array<std::string_view, 8> ALL_STATE_STRINGS = {
        "starting",
        "downloadingMetadata", 
        "downloading",
        "seeding",
        "paused",
        "error",
        "stopped",
        "unknown"
    };

    // Parse string back to enum (runtime function)
    constexpr TorrentState stringToState(std::string_view str) noexcept
    {
        if (str == "starting") return TorrentState::Starting;
        if (str == "downloadingMetadata") return TorrentState::DownloadingMetadata;
        if (str == "downloading") return TorrentState::Downloading;
        if (str == "seeding") return TorrentState::Seeding;
        if (str == "paused") return TorrentState::Paused;
        if (str == "error") return TorrentState::Error;
        if (str == "stopped") return TorrentState::Stopped;
        return TorrentState::Error; // Default fallback
    }

} // namespace tc