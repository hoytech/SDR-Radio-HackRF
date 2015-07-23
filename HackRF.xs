#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


#include <stdlib.h>
#include <stdint.h>

#define MATH_INT64_NATIVE_IF_AVAILABLE
#include "perl_math_int64.h"


#include <libhackrf/hackrf.h>



struct hackrf_context {
  hackrf_device* device;

  int signalling_fd;
  uint64_t bytes_needed;
  void *buffer;
};


static int number_of_hackrf_inits = 0;




static int _tx_callback(hackrf_transfer* transfer) {
  char junk = '\x00';
  struct hackrf_context *ctx = (struct hackrf_context *)transfer->tx_ctx;
  ssize_t result;

  ctx->bytes_needed = transfer->valid_length;
  ctx->buffer = transfer->buffer;

  result = write(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();
  result = read(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();

  return 0;
}




MODULE = Radio::HackRF         PACKAGE = Radio::HackRF
PROTOTYPES: ENABLE


BOOT:
  PERL_MATH_INT64_LOAD_OR_CROAK;




struct hackrf_context *
new_context()
    CODE:
        int result;
        struct hackrf_context *ctx;

        ctx = malloc(sizeof(struct hackrf_context));

        result = hackrf_init();

        if (result != HACKRF_SUCCESS) {
          free(ctx);
          croak("hackrf_init() failed: %s (%d)\n", hackrf_error_name(result), result);
        }

        number_of_hackrf_inits++;

        result = hackrf_open(&ctx->device);

        if (result != HACKRF_SUCCESS) {
          free(ctx);
          croak("hackrf_open() failed: %s (%d)\n", hackrf_error_name(result), result);
        }

        RETVAL = ctx;

    OUTPUT:
        RETVAL



void
_set_signalling_fd(ctx, fd)
        struct hackrf_context *ctx
        int fd
    CODE:
        ctx->signalling_fd = fd;



uint64_t
_get_bytes_needed(ctx)
        struct hackrf_context *ctx
    CODE:
        RETVAL = ctx->bytes_needed;

    OUTPUT:
        RETVAL







void
_start_tx(ctx)
        struct hackrf_context *ctx
    CODE:
        int result;

        result = hackrf_set_txvga_gain(ctx->device, 30);
        result |= hackrf_start_tx(ctx->device, _tx_callback, ctx);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_start_tx() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void
_set_amp_enable(ctx, enabled)
        struct hackrf_context *ctx
        int enabled
    CODE:
        int result;

        result = hackrf_set_amp_enable(ctx->device, enabled ? 1 : 0);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_set_amp_enable() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void
_set_freq(ctx, freq)
        struct hackrf_context *ctx
        uint64_t freq
    CODE:
        int result;

        result = hackrf_set_freq(ctx->device, freq);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_set_freq() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void
_set_sample_rate(ctx, sample_rate)
        struct hackrf_context *ctx
        unsigned long sample_rate
    CODE:
        int result;

        result = hackrf_set_sample_rate_manual(ctx->device, sample_rate, 1);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_set_sample_rate_manual() failed: %s (%d)\n", hackrf_error_name(result), result);
        }
