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
  void *buffer;
  uint64_t buffer_size;
};


static int number_of_hackrf_inits = 0;

static volatile sig_atomic_t terminate_callback = 0;


static int _transfer_callback(hackrf_transfer* transfer, struct hackrf_context *ctx) {
  char junk = '\x00';
  ssize_t result;

  if (terminate_callback) {
    terminate_callback = 0;
    result = write(ctx->signalling_fd, &junk, 1);
    if (result != 1) abort();
    return -1;
  }

  ctx->buffer_size = transfer->valid_length;
  ctx->buffer = transfer->buffer;

  result = write(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();
  result = read(ctx->signalling_fd, &junk, 1);
  if (result != 1) abort();

  return 0;
}

static int _tx_callback(hackrf_transfer* transfer) {
  struct hackrf_context *ctx = (struct hackrf_context *)transfer->tx_ctx;

  return _transfer_callback(transfer, ctx);
}

static int _rx_callback(hackrf_transfer* transfer) {
  struct hackrf_context *ctx = (struct hackrf_context *)transfer->rx_ctx;

  return _transfer_callback(transfer, ctx);
}





MODULE = SDR::Radio::HackRF         PACKAGE = SDR::Radio::HackRF
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
_get_buffer_size(ctx)
        struct hackrf_context *ctx
    CODE:
        RETVAL = ctx->buffer_size;

    OUTPUT:
        RETVAL




void
_copy_to_buffer(ctx, bytes_sv)
        struct hackrf_context *ctx
        SV *bytes_sv
    CODE:
        char *bytes;
        size_t bytes_size;

        if (!SvPOK(bytes_sv)) croak("bytes is not a string");
        bytes_size = SvCUR(bytes_sv);
        bytes = SvPV(bytes_sv, bytes_size);

        if (bytes_size != ctx->buffer_size) croak("source string is the wrong size %lu vs %lu", bytes_size, ctx->buffer_size);

        memcpy(ctx->buffer, bytes, bytes_size);



SV *
_copy_from_buffer(ctx)
        struct hackrf_context *ctx
    CODE:
        SV *output;
        char *outputp;

        output = newSVpvn("", 0);
        SvGROW(output, ctx->buffer_size);
        SvCUR_set(output, ctx->buffer_size);
        outputp = SvPV(output, ctx->buffer_size);

        memcpy(outputp, ctx->buffer, ctx->buffer_size);

        RETVAL = output;

    OUTPUT:
        RETVAL


void
_start_tx(ctx)
        struct hackrf_context *ctx
    CODE:
        int result;

        result = hackrf_set_txvga_gain(ctx->device, 40);
        result |= hackrf_start_tx(ctx->device, _tx_callback, ctx);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_start_tx() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void
_start_rx(ctx)
        struct hackrf_context *ctx
    CODE:
        int result;

        result = hackrf_set_vga_gain(ctx->device, 32);
        result |= hackrf_set_lna_gain(ctx->device, 32);
        result |= hackrf_start_rx(ctx->device, _rx_callback, ctx);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_start_rx() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void _set_terminate_callback_flag(ctx)
        struct hackrf_context *ctx
    CODE:
        terminate_callback = 1;


void _stop_tx(ctx)
        struct hackrf_context *ctx
    CODE:
        int result;

        result = hackrf_stop_tx(ctx->device);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_stop_tx() failed: %s (%d)\n", hackrf_error_name(result), result);
        }

        // disable amp as safety precaution

        result = hackrf_set_amp_enable(ctx->device, 0);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_set_amp_enable() failed: %s (%d)\n", hackrf_error_name(result), result);
        }


void _stop_rx(ctx)
        struct hackrf_context *ctx
    CODE:
        int result;

        result = hackrf_stop_rx(ctx->device);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_stop_rx() failed: %s (%d)\n", hackrf_error_name(result), result);
        }

        // disable amp as safety precaution

        result = hackrf_set_amp_enable(ctx->device, 0);

        if (result != HACKRF_SUCCESS) {
          croak("hackrf_set_amp_enable() failed: %s (%d)\n", hackrf_error_name(result), result);
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
