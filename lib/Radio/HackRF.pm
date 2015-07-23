package Radio::HackRF;

our $VERSION = '0.100';

use common::sense;
use AnyEvent;
use AnyEvent::Util;

use Inline::Module::LeanDist C => 'DATA', libs => '-lhackrf';


sub new {
  my ($class, %args) = @_;

  my $self = {};
  bless $self, $class;

  $self->{ctx} = new_context();

  ($self->{perl_side_signalling_fh}, $self->{c_side_signalling_fh}) = AnyEvent::Util::portable_socketpair();

  die "couldn't create signalling socketpair: $!" if !$self->{perl_side_signalling_fh};

  _set_signalling_fd($self->{ctx}, fileno($self->{c_side_signalling_fh}));

  ## always turn off unless actually requested
  _set_amp_enable($self->{ctx}, $args{amp_enable} ? 1 : 0);

  if (exists $args{freq}) {
    _set_freq($self->{ctx}, $args{freq});
  }

  if (exists $args{sample_rate}) {
    _set_sample_rate($self->{ctx}, $args{sample_rate});
  }

  return $self;
}

sub tx {
  my ($self, $cb) = @_;

  die "already in $self->{state} state" if $self->{state};
  $self->{state} = 'TX';

  $self->{pipe_watcher} = AE::io $self->{perl_side_signalling_fh}, 0, sub {
print "BING\n";
    sysread $self->{perl_side_signalling_fh}, my $junk, 1; ## FIXME: non-blocking
print "BING 2\n";

    my $bytes_needed = _get_bytes_needed($self->{ctx});

    $cb->($bytes_needed);
    print "OMFG: $bytes_needed\n";

    syswrite $self->{perl_side_signalling_fh}, "\x00";
print "BONG\n";
  };

  _start_tx($self->{ctx});
}



sub run {
  my ($self) = @_;

  $self->{cv} = AE::cv;

  $self->{cv}->recv;
}



1;



__DATA__
__C__

#include <libhackrf/hackrf.h>


struct hackrf_context {
  hackrf_device* device;

  int signalling_fd;
  uint64_t bytes_needed;
  void *buffer;
};


static int number_of_hackrf_inits = 0;

void *new_context() {
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

  return (void *) ctx;
}



void _set_signalling_fd(void *ctx_void, int fd) {
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;

  ctx->signalling_fd = fd;
}

unsigned long _get_bytes_needed(void *ctx_void) {
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;

  return ctx->bytes_needed;
}






void _tx_callback(hackrf_transfer* transfer) {
  char junk = '\x00';
  struct hackrf_context *ctx = (struct hackrf_context *)transfer->tx_ctx;

  ctx->bytes_needed = transfer->valid_length;
  ctx->buffer = transfer->buffer;

printf("OMG IN TX CALLBACK!\n");
  (void)write(ctx->signalling_fd, &junk, 1);
  (void)read(ctx->signalling_fd, &junk, 1);
}

void _start_tx(void *ctx_void) {
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;
  int result;

  result = hackrf_set_txvga_gain(ctx->device, 30);
  result |= hackrf_start_tx(ctx->device, _tx_callback, ctx);

  if (result != HACKRF_SUCCESS) {
    croak("hackrf_start_tx() failed: %s (%d)\n", hackrf_error_name(result), result);
  }
}





void _set_amp_enable(void *ctx_void, int enabled) {
  int result;
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;

  result = hackrf_set_amp_enable(ctx->device, enabled ? 1 : 0);

  if (result != HACKRF_SUCCESS) {
    croak("hackrf_set_amp_enable() failed: %s (%d)\n", hackrf_error_name(result), result);
  }
}


void _set_freq(void *ctx_void, unsigned long freq) { // FIXME: 32 bit systems
  int result;
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;

  result = hackrf_set_freq(ctx->device, freq);

  if (result != HACKRF_SUCCESS) {
    croak("hackrf_set_freq() failed: %s (%d)\n", hackrf_error_name(result), result);
  }
}

void _set_sample_rate(void *ctx_void, unsigned long sample_rate) {
  int result;
  struct hackrf_context *ctx = (struct hackrf_context *)ctx_void;

  result = hackrf_set_sample_rate_manual(ctx->device, sample_rate, 1);

  if (result != HACKRF_SUCCESS) {
    croak("hackrf_set_sample_rate_manual() failed: %s (%d)\n", hackrf_error_name(result), result);
  }
}



__END__

=encoding utf-8

=head1 NAME

Radio::HackRF - Control HackRF software defined radio

=head1 SYNOPSIS

    my $h = Radio::HackRF->new(
              frequency => 35_000_000,
              sample_rate => 8_000_000,
              tx_if_gain => 20,
              cb => sub {
                my $seq = sequence($duration * $sample_rate);

                my $iq_data = $amp_scale * cos(2 * pi * ($freq/$sample_rate) * $seq)
                              + ($amp_scale * i * sin(2 * pi * ($freq/$sample_rate) * $seq));

                my $scaled = $iq_data + $dc_offset + ($dc_offset * i);

                return $scaled->byte;
              },
            );

=head1 DESCRIPTION

=head1 SEE ALSO

L<Radio-HackRF github repo|https://github.com/hoytech/Radio-HackRF>

=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>

=head1 COPYRIGHT & LICENSE

Copyright 2015 Doug Hoyte.

This module is licensed under the same terms as perl itself.
