#include "simple_torrent_native.h"

#include <cstddef>
#include <cstdint>

namespace {

#if defined(SIMPLE_TORRENT_EMBEDDED_CA_BUNDLE)
constexpr std::uint8_t kEmbeddedCaBundle[] = {
#include "simple_torrent_embedded_ca_bundle.inc"
};
#endif

}  // namespace

extern "C" STN_API const std::uint8_t* simple_torrent_embedded_ca_bundle(
    std::size_t* size_out) {
  if (size_out == nullptr) {
    return nullptr;
  }
#if defined(SIMPLE_TORRENT_EMBEDDED_CA_BUNDLE)
  *size_out = sizeof(kEmbeddedCaBundle);
  return kEmbeddedCaBundle;
#else
  *size_out = 0;
  return nullptr;
#endif
}
