use common::sense;

use PDL;
use PDL::Complex;
use PDL::Constants qw(PI);

use Radio::HackRF;



my $sample_rate = 8_000_000;
my $freq = 470_000;
my $amp_scale = 50;
my $pulse_width = 0.0005;
my $dc_offset = 5;



my $command_to_pulses_map = {
  U => 10,
  D => 52,
  L => 58,
  R => 64,

  UL => 28,
  UR => 34,
  DL => 52,
  DR => 46,
};


sub generate_base_sequence {
  my $pulses = shift;

  my @message = (
                  qw(1 1 1 0) x 4,
                  qw(1 0) x $pulses,
                );

  my $signal = rld(ones(scalar @message) * $pulse_width * $sample_rate,
                   pdl(@message));


  my $sample_sequence = sequence($signal->getdim(0)) * 2 * PI * ($freq/$sample_rate);

  my $carrier = cos($sample_sequence) + (i * sin($sample_sequence));

  $carrier *= $amp_scale;


  my $product = $signal * $carrier;

  $product += $dc_offset + ($dc_offset * i);


  return $product->byte->flat;
}



my $h = Radio::HackRF->new(freq => 35_000_000, sample_rate => $sample_rate);


my $cmd = 'D';
my $signal;


$h->tx(sub {
  my $block_size = shift;

  if (!defined $cmd) {
    $signal = undef;
    return;
  }

  if (!defined $signal) {
    $signal = generate_base_sequence($command_to_pulses_map->{$cmd});
  }

  my $transmission = $signal->slice("0:" . ($block_size - 1));

  $signal = $signal->rotate(-$block_size);

  return $transmission->get_dataref;
});

my $z; $z = AE::timer 1, 0, sub {
  print "SWITCHING TO UP\n";
  $cmd = 'U';
  $signal = undef;
  $z = AE::timer 1, 0, sub {
    print "SWITCHING OFF\n";
    $cmd = undef;
  };
};

$h->run;
