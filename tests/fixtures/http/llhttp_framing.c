#include "llhttp.h"
#include <stdio.h>
#include <string.h>

int main(void) {
  const char *invalid[] = {
    "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding:\r\nContent-Length: 1\r\n\r\nx",
    "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: \t\r\nContent-Length: 1\r\n\r\nx"
  };
  for (unsigned i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
    llhttp_t parser;
    llhttp_settings_t settings;
    llhttp_settings_init(&settings);
    llhttp_init(&parser, HTTP_REQUEST, &settings);
    if (llhttp_execute(&parser, invalid[i], strlen(invalid[i])) != HPE_INVALID_TRANSFER_ENCODING) {
      fprintf(stderr, "empty Transfer-Encoding was not rejected\n");
      return 1;
    }
  }
  llhttp_t parser;
  llhttp_settings_t settings;
  llhttp_settings_init(&settings);
  llhttp_init(&parser, HTTP_REQUEST, &settings);
  const char *valid = "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1\r\n\r\nx";
  if (llhttp_execute(&parser, valid, strlen(valid)) != HPE_OK) return 2;
  if (LLHTTP_VERSION_MAJOR != 9 || LLHTTP_VERSION_MINOR != 4 || LLHTTP_VERSION_PATCH != 3) return 3;
  puts("llhttp 9.4.3 framing regressions passed");
  return 0;
}
