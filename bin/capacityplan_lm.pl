#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            ();
use Games::Lacuna::Client ();

use constant MINUTE => 60;
use constant HOUR   => 3600;

# API call count
my $i = 0;

my $cfg_file = shift(@ARGV) || 'lacuna.yml';
unless ( $cfg_file and -e $cfg_file ) {
  die "Did not provide a config file";
}

my $client = Games::Lacuna::Client->new(
  cfg_file => $cfg_file,
  # debug    => 1,
);

# Load the planets
print ++$i . " - Loading empire $client->{name}...\n";
my $empire  = $client->empire->get_status->{empire};
my $planets = $empire->{planets};

# Potential build options
my @options = ();

my %total_hour;

# Scan each planet
foreach my $planet_id ( sort keys %$planets ) {
  my $name = $planets->{$planet_id};
  print ++$i . " - Loading planet $name...\n";

  # Load planet data
  my $planet    = $client->body( id => $planet_id );
  my $result    = $planet->get_buildings;
  my $body      = $result->{status}->{body};
  my $buildings = $result->{buildings};
  next if $body->{type} eq "space station";

  # Find the Development Ministry
  my $development_id = List::Util::first {
    $buildings->{$_}->{name} eq 'Development Ministry'
  } keys %$buildings;
  my $development_slots = $development_id
    ? ($buildings->{$development_id}->{level} + 1)
    : 1;

  # How many remaining build slots are there?
  my $pending_build = scalar grep { $_->{pending_build} } values %$buildings;
  my $can_build     = $development_slots - $pending_build;

  # Analysis
  foreach my $type ( qw{ food ore water energy waste happiness } ) {
    my $capacity = 0;
    my $stored   = 0;
    my $hour     = 0;
    my $storage  = 0;

    if ($type ne "happiness") {
      $capacity = $body->{"${type}_capacity"};
      $stored   = $body->{"${type}_stored"};
      $hour     = $body->{"${type}_hour"};
      $storage  = $capacity - $stored;
      $total_hour{$type} += $hour;
    }
    else {
      $hour     = $body->{"${type}_hour"};
      $stored   = $body->{"$type"};
      $capacity = $stored;
      $total_hour{happiness} += $hour;
    }

    my $label    = ucfirst($type);
                my $time; my $left;
                if ($hour == 0) {
                  $time     = 0;
                  $left     = 0;
                }
                elsif ($hour > 0) {
                  $time     = int( $capacity / $hour );
                  $left     = int( $storage  / $hour );
                }
                else {
                  $time = "000";
                  $left = int($stored / $hour) * -1;
                }

    # Is there a building we can upgrade?
    my $building = {
      food   => 'Food Reserve',
      ore    => 'Ore Storage Tanks',
      water  => 'Water Storage Tank',
      energy => 'Energy Reserve',
      waste  => 'Waste Sequestration Well',
      happiness => 'None',
    }->{$type};

    my @upgrade = grep {
      $_->{name} eq $building
      and not
      $_->{pending_build}
    } values %$buildings;
    my @already = grep {
      $_->{name} eq $building
      and
      $_->{pending_build}
    } values %$buildings;

    $capacity = "0" if ($type eq "happiness");
    printf "%15s - %9s - %18d/%18d %5d:%5d %12d rate",
                       $name, $label, $stored, $capacity, $time, $left, $hour;
    print " UPGRADING..." if @already;
    print "\n";

    next unless $can_build;
    next unless @upgrade;
    next if     @already;
    next if $time   < 0;
    next if $left   < 0;
    next if $stored <= 0;
    if ( $time > 10 and $left > 10 ) {
      next;
    }
                if ( $time eq "000" and $left > 10) {
      next;
    }

    # Save as an option
    push @options, {
      planet   => $planet_id,
      name     => $name,
      type     => $type,
      capacity => $capacity,
      stored   => $stored,
      hour     => $hour,
      time     => $time,
      left     => $left,
      label    => $label,
      upgrade  => \@upgrade,
    };
  }
}

# Print build options in order 
@options = sort {
  $a->{time} > $b->{time}
  or
  $a->{left} > $b->{left}
} @options;


foreach my $type ( qw{ food ore water energy waste happiness } ) {
  printf "%15d %s\n", $total_hour{$type}, $type;
}
# Print out the options
#my $n = 0;
#print "\n\n";
#print "Recommended Storage Capacity Upgrades\n";
#print "-------------------------------------\n";
#foreach my $option ( @options ) {
#  printf "Option %2d - %15s - %7s - %3dh capacity - %3dh lef\n",
#           ++$n, $option->{name}, $option->{label}, $option->{time}, $option->{left};
#}

exit(0);

sub output {
  my $str = join ' ', @_;
  $str .= "\n" if $str !~ /\n$/;
  print "[" . localtime() . "] " . $str;
}

sub get_amts {
}
