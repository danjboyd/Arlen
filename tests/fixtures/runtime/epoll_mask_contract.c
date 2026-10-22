#include <stdint.h>
#include <stdio.h>

// These are the actual field widths in libdispatch's dispatch_muxnote_s.
typedef struct dispatch_muxnote_s {
  uint32_t dmn_events;
  uint16_t dmn_disarmed_events;
} *dispatch_muxnote_t;

// The test generates this header from the exact new return line in the pinned
// compatibility patch. The mathematical reference below uses XOR, independently
// of integer promotion/complement rules in the implementation under test.
#include "epoll_mask_under_test.h"

int main(void) {
  const uint32_t masks[] = {0, 1, 4, 5, UINT32_MAX, UINT32_C(0x80000000),
      UINT32_C(0x40000000), UINT32_C(0x80000001), UINT32_C(0x40000004),
      UINT32_C(0xdeadbeef), UINT32_C(0xaaaa5555), UINT32_C(0x5555aaaa)};
  unsigned long cases = 0;
  for (uint32_t disarmed = 0; disarmed <= UINT16_MAX; disarmed++) {
    for (unsigned int index = 0; index < sizeof(masks) / sizeof(masks[0]); index++) {
      struct dispatch_muxnote_s note = {masks[index], (uint16_t)disarmed};
      uint32_t expected = masks[index] ^ (masks[index] & disarmed);
      if (armed_events_under_test(&note) != expected) return 1;
      cases++;
    }
  }
  printf("pass:epoll-mask-preserves-32-bit-events %lu cases\n", cases);
  return 0;
}
