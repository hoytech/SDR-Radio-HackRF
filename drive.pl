use common::sense;

use PDL;
use PDL::Complex;


sub pi () { 3.14159265358979 }


use Radio::HackRF;


my $sample_rate = 8_000_000;
my $freq = 470_000;
my $amp_scale = 50;
my $pulse_width = 0.0005;
my $dc_offset = 5;



my $message = ('1110' x 4) . ('10' x 10);

my $signal = rld(ones(length($message)) * $pulse_width * $sample_rate,
                 pdl(split //, $message));


my $carrier = sequence($signal->getdim(0));

$carrier = $amp_scale * cos(2 * pi * ($freq/$sample_rate) * $carrier)
           + ($amp_scale * i * sin(2 * pi * ($freq/$sample_rate) * $carrier));


my $iq_data = $signal * $carrier;

my $scaled = $iq_data + $dc_offset + ($dc_offset * i);

my $output = $scaled->byte->flat;



my $h = Radio::HackRF->new(freq => 35_000_000, sample_rate => $sample_rate);

$h->tx(sub {
  my $block_size = shift;

  my $ret = $output->slice("0:" . ($block_size - 1));

  $output = $output->rotate(-$block_size);

  return $ret->get_dataref;
});

$h->run;
