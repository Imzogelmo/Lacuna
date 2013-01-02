#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long          (qw(GetOptions));
use List::Util            (qw(first max));
use JSON;
use utf8;

  binmode STDOUT, ":utf8";

  my $log_dir = "log";

  my %opts = (
    h        => 0,
    v        => 0,
    input     => $log_dir . '/battle_log.js',
  );

  GetOptions(\%opts,
    'h|help',
    'input=s',
    'v|verbose',
  );
  
  usage() if $opts{h};

  my $json = JSON->new->utf8(1);

  my $idata = get_json($opts{input});
  unless ($idata) {
    die "Could not read $opts{input}\n";
  }

  print "A,E,Ship,D,E,Def,Win,Date\n";
  for my $battle (@$idata) {
    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
            $battle->{attacked_body},
            $battle->{attacked_body_id},
            $battle->{attacked_empire},
            $battle->{attacked_empire_id},
            $battle->{attacking_body},
            $battle->{attacking_body_id},
            $battle->{attacking_empire},
            $battle->{attacking_empire_id},
            $battle->{attacking_unit},
            $battle->{date},
            $battle->{defending_body},
            $battle->{defending_body_id},
            $battle->{defending_empire},
            $battle->{defending_empire_id},
            $battle->{defending_unit},
            $battle->{victory_to},
  }
exit;

sub get_json {
  my ($file) = @_;

  if (-e $file) {
    my $fh; my $lines;
    open($fh, "$file") || die "Could not open $file\n";
    $lines = join("", <$fh>);
    return 0 unless ($lines);
    my $data = $json->utf8->decode($lines);
    close($fh);
    return $data;
  }
  else {
    warn "$file not found!\n";
  }
  return 0;
}

sub usage {
    diag(<<END);
Usage: $0 --feedfile file

Options:
  --help            - Prints this out
  --verbose         - Print more details.
  --input  sift  - Where to get data
END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
