use common::sense;

use Radio::HackRF;

use PDL;
use PDL::Complex;
use PDL::Constants qw(PI);
use PDL::DSP::Fir::Simple;


my $freq = shift || 104.5;
$freq *= 1_000_000;


my $rf_sample_rate = 2_000_000;
my $audio_sample_rate = 48_000;


my $h = Radio::HackRF->new(freq => $freq, sample_rate => $rf_sample_rate, amp_enable => 1);


open(my $fh, '|-:raw', "pacat --stream-name fmrecv --format float32le --rate $audio_sample_rate --channels 1 --latency-msec 10")
  || die "couldn't run pacat (install pulse-audio?): $!";


$h->rx(sub {
  my $data = pdl()->convert(byte)->reshape(length($_[0]));

  ${ $data->get_dataref } = $_[0];
  $data->upd_data();

  $data = $data->convert(float);

  $data -= 128;
  $data *= 1000000;


  my $I = $data->slice([0,-1,2]);
  my $Q = $data->slice([1,-1,2]);


  ## Decimate 4:1

  $I = $I->slice([0,-1,4]);
  $Q = $Q->slice([0,-1,4]);


  ## LPF

  $I = PDL::DSP::Fir::Simple::filter($I, { fc => 0.25, N => 64 });
  $Q = PDL::DSP::Fir::Simple::filter($Q, { fc => 0.25, N => 64 });


  ## Demod

  my $aI = $I->slice([0, -2]);
  my $aQ = $Q->slice([0, -2]);

  my $bI = $I->slice([1, -1]);
  my $bQ = $Q->slice([1, -1]);

  my $a = $aI + (i * $aQ);
  my $b = $bI + (i * $bQ);
  my $angle = $a * $b->Cconj();
  $angle = $angle->Carg();

  $angle = $angle->append(pdl(0)); ## FIXME: retain previous values


  ## Decimate 10:1, then 25:24, then LPF

  $angle = $angle->slice([0,-1,10]);

  $angle = $angle->reshape(25,$angle->getdim(0) / 25)->slice([0,-2],[0,-1])->flat;

  $angle = PDL::DSP::Fir::Simple::filter($angle, { fc => 0.4, N => 64 });


  my $output = $angle->convert(float);

  print $fh ${ $output->get_dataref };
});


$h->run;
