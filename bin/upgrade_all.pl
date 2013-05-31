#!/usr/bin/env perl
#
# Simple program for upgrading buildings

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Games::Lacuna::Client;
use Getopt::Long qw(GetOptions);
use JSON;
use Exception::Class;

  our %opts = (
        h => 0,
        v => 0,
        maxlevel => 30,
        config => "lacuna.yml",
        dumpfile => "log/all_builds.js",
        station => 0,
        wait    => 8 * 60 * 60,
        sleep  => 1,
        extra  => [],
        skip   => [],
  );

  GetOptions(\%opts,
    'h|help',
    'v|verbose',
    'planet=s@',
    'config=s',
    'dumpfile=s',
    'maxlevel=i',
    'dry',
    'wait=i',
    'junk',
    'space',
    'city',
    'lab',
    'match=s@',
    'skip=s@',
    'extra=s@',
    'sleep=i',
  );

  usage() if $opts{h};
  
  set_items();
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config} || "lacuna.yml",
    rpc_sleep => $opts{sleep},
    # debug    => 1,
  );

  my $json = JSON->new->utf8(1);
  $json = $json->pretty([1]);
  $json = $json->canonical([1]);
  open(OUTPUT, ">", $opts{dumpfile}) || die "Could not open $opts{dumpfile} for writing";

  my $status;
  my $empire = $glc->empire->get_status->{empire};
  print "Starting RPC: $glc->{rpc_count}\n";

# Get planets
  my %planets = map { $empire->{planets}{$_}, $_ } keys %{$empire->{planets}};
  $status->{planets} = \%planets;
  my $short_time = $opts{wait} + 1;

  my $keep_going = 1;
  do {
    my $pname;
    my @skip_planets;
    for $pname (sort keys %planets) {
      if ($opts{planet} and not (grep { $pname eq $_ } @{$opts{planet}})) {
        push @skip_planets, $pname;
        next;
      }
      print "Inspecting $pname\n";
      my $planet    = $glc->body(id => $planets{$pname});
      my $result    = $planet->get_buildings;
      my $buildings = $result->{buildings};
      my $station = $result->{status}{body}{type} eq 'space station' ? 1 : 0;
      if ($station) {
        push @skip_planets, $pname;
        next;
      }
      my ($sarr, $pending) = bstats($buildings, $station);
      my $seconds = $opts{wait} + 1;
      $seconds = $pending if ($pending > 0);
      for my $bld (@$sarr) {
        my $ok;
        my $bldstat = "Bad";
        my $reply = "";
        $ok = eval {
          my $type = get_type_from_url($bld->{url});
          my $bldpnt = $glc->building( id => $bld->{id}, type => $type);
          if ($opts{dry}) {
            $reply = "dry run";
            $seconds = $opts{wait} + 1;
          }
          else {
            $reply = "upgrading";
            $bldstat = $bldpnt->upgrade();
            $seconds = $bldstat->{building}->{pending_build}->{seconds_remaining} - 15;
          }
        };
        printf "%7d %10s l:%2d x:%2d y:%2d %s\n",
                 $bld->{id}, $bld->{name},
                 $bld->{level}, $bld->{x}, $bld->{y}, $reply;
        unless ($ok) {
          print "$@ Error; sleeping 60\n";
#          sleep 60;
        }
      }
      $status->{"$pname"} = $sarr;
      if ($seconds > $opts{wait}) {
        print "Queue of ", sec2str($seconds),
              " is longer than wait period of ",sec2str($opts{wait}), ", taking $pname off of list.\n";
        push @skip_planets, $pname;
      }
      elsif ($seconds < $short_time) {
        $short_time = $seconds;
      }
    }
    print "Done with: ",join(":", sort @skip_planets), "\n";
    for $pname (@skip_planets) {
      delete $planets{$pname};
    }
    if (keys %planets) {
      print "Clearing Queue for ",sec2str($short_time),".\n";
      sleep $short_time;
    }
    else {
      print "Nothing Else to do.\n";
      $keep_going = 0;
    }
  } while ($keep_going);

 print OUTPUT $json->pretty->canonical->encode($status);
 close(OUTPUT);
 print "Ending   RPC: $glc->{rpc_count}\n";

exit;

sub set_items {
  my $unless = [
  "Beach [1]",
  "Beach [10]",
  "Beach [11]",
  "Beach [12]",
  "Beach [13]",
  "Beach [2]",
  "Beach [3]",
  "Beach [4]",
  "Beach [5]",
  "Beach [6]",
  "Beach [7]",
  "Beach [8]",
  "Beach [9]",
  "Crater",
  "Essentia Vein",
  "Fissure",
  "Gas Giant Settlement Platform",
  "Grove of Trees",
  "Lagoon",
  "Lake",
  "Rocky Outcropping",
  "Patch of Sand",
  "Subspace Supply Depot",
  "Supply Pod",
  "The Dillon Forge",
  ];
  my $junk = [
    "Great Ball of Junk",
    "Junk Henge Sculpture",
    "Metal Junk Arches",
    "Pyramid Junk Sculpture",
    "Space Junk Park",
  ];
  my $glyph = [
  "Algae Pond",
  "Amalgus Meadow",
  "Beeldeban Nest",
  "Black Hole Generator",
  "Citadel of Knope",
  "Crashed Ship Site",
  "Denton Brambles",
  "Geo Thermal Vent",
  "Gratch's Gauntlet",
  "Interdimensional Rift",
  "Kalavian Ruins",
  "Kastern's Keep",
  "Lapis Forest",
  "Library of Jith",
  "Malcud Field",
  "Massad's Henge",
  "Natural Spring",
  "Oracle of Anid",
  "Pantheon of Hagness",
  "Ravine",
  "Temple of the Drajilites",
  "Volcano",
  ];
  my $space = [
    "Space Port",
  ];
  my $city = [
    "Lost City of Tyleon (A)",
    "Lost City of Tyleon (B)",
    "Lost City of Tyleon (C)",
    "Lost City of Tyleon (D)",
    "Lost City of Tyleon (E)",
    "Lost City of Tyleon (F)",
    "Lost City of Tyleon (G)",
    "Lost City of Tyleon (H)",
    "Lost City of Tyleon (I)",
  ];
  my $lab = [
    "Space Station Lab (A)",
    "Space Station Lab (B)",
    "Space Station Lab (C)",
    "Space Station Lab (D)",
  ];
  if ($opts{junk}) {
    push @{$opts{extra}}, @$junk;
  }
  else {
    push @{$opts{skip}}, @$junk;
  }
  if ($opts{glyph}) {
    push @{$opts{extra}}, @$glyph;
  }
  else {
    push @{$opts{skip}}, @$glyph;
  }
  if ($opts{space}) {
    push @{$opts{extra}}, @$space;
  }
  else {
    push @{$opts{skip}}, @$space;
  }
  if ($opts{city}) {
    push @{$opts{extra}}, @$city;
  }
  else {
    push @{$opts{skip}}, @$city;
  }
  if ($opts{lab}) {
    push @{$opts{extra}}, @$lab;
  }
  else {
    push @{$opts{skip}}, @$lab;
  }
  push @{$opts{skip}}, @$unless;

#  print "Extra: ",join(", ", @{$opts{extra}}), "\n";
#  print "Skip : ",join(", ", @{$opts{skip}}), "\n";
}

sub bstats {
  my ($bhash, $station) = @_;

  my $bcnt = 0;
  my $dlevel = $station ? 121 : 0;
  my @sarr;
  my $pending = 0;
  for my $bid (keys %$bhash) {
    if ($bhash->{$bid}->{name} eq "Development Ministry") {
      $dlevel = $bhash->{$bid}->{level};
    }
    if ( defined($bhash->{$bid}->{pending_build})) {
      $bcnt++;
      $pending = $bhash->{$bid}->{pending_build}->{seconds_remaining} if ($bhash->{$bid}->{pending_build}->{seconds_remaining} > $pending);
    }
    else {
      my $doit = check_type($bhash->{$bid});
      if ($doit) {
#        print "Doing $bhash->{$bid}->{name}\n";
        my $ref = $bhash->{$bid};
        $ref->{id} = $bid;
        push @sarr, $ref if ($ref->{level} < $opts{maxlevel} && $ref->{efficiency} == 100);
      }
      else {
#        print "Skip  $bhash->{$bid}->{name}\n";
      }
    }
  }
  @sarr = sort { $a->{level} <=> $b->{level} ||
                 $a->{x} <=> $b->{x} ||
                 $a->{y} <=> $b->{y} } @sarr;
  if (scalar @sarr > ($dlevel + 1 - $bcnt)) {
    splice @sarr, ($dlevel + 1 - $bcnt);
  }
  return (\@sarr, $pending);
}

sub check_type {
  my ($bld) = @_;
  
  print "Checking $bld->{name} - ";
  if ($opts{match}) {
    if (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{match}}) {
      print "Match\n";
      return 1;
    }
    else {
      print "No match\n";
      return 0;
    }
  }
  if ($opts{extra} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{extra}})) {
    print "Extra\n";
    return 1;
  }
  if ($opts{skip} and (grep { $bld->{name} =~ /\Q$_\E/ } @{$opts{skip}})) {
    print "Skipping\n";
    return 0;
  }
  print "Default\n";
  return 1;
}

sub sec2str {
  my ($sec) = @_;

  my $day = int($sec/(24 * 60 * 60));
  $sec -= $day * 24 * 60 * 60;
  my $hrs = int( $sec/(60*60));
  $sec -= $hrs * 60 * 60;
  my $min = int( $sec/60);
  $sec -= $min * 60;
  return sprintf "%04d:%02d:%02d:%02d", $day, $hrs, $min, $sec;
}

sub get_type_from_url {
  my ($url) = @_;

  my $type;
  eval {
    $type = Games::Lacuna::Client::Buildings::type_from_url($url);
  };
  if ($@) {
    print "Failed to get building type from URL '$url': $@";
    return 0;
  }
  return 0 if not defined $type;
  return $type;
}

sub usage {
    diag(<<END);
Usage: $0 [options]

This program upgrades planets on your planet. Faster than clicking each port.
It will upgrade in order of level up to maxlevel.

Options:
  --help             - This info.
  --verbose          - Print out more information
  --config <file>    - Specify a GLC config file, normally lacuna.yml.
  --planet <name>    - Specify planet
  --dumpfile         - data dump for all the info we don't print
  --maxlevel         - do not upgrade if this level has been achieved.
  --wait             - Max number of seconds to wait to repeat loop.
  --sleep            - Pause between RPC calls. Default 1.
  --junk             - Upgrade Junk Buildings.
  --glyph            - Upgrade Glyph Buildings.
  --space            - Upgrade spaceports.
  --city             - Upgrade LCOT
  --lab              - Upgrade labs
  --match            - Only upgrade matching building names.
  --skip             - Skip building names (multiple allowed).
  --extra            - Add matching names to usual list to upgrade.
  --dry              - Do not actually upgrade.
  );
END
  my $bld_names = bld_names();
  print "\nBuilding Names: ",join(", ", sort @$bld_names ),"\n";
  exit 1;
}

sub verbose {
    return unless $opts{v};
    print @_;
}

sub output {
    return if $opts{q};
    print @_;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}

sub normalize_planet {
    my ($planet_name) = @_;

    $planet_name =~ s/\W//g;
    $planet_name = lc($planet_name);
    return $planet_name;
}

sub bld_names {
  my $bld_names = [
  "Algae Cropper",
  "Algae Pond",
  "Amalgus Meadow",
  "Apple Orchard",
  "Archaeology Ministry",
  "Art Museum",
  "Atmospheric Evaporator",
  "Beach [1]",
  "Beach [10]",
  "Beach [11]",
  "Beach [12]",
  "Beach [13]",
  "Beach [2]",
  "Beach [3]",
  "Beach [4]",
  "Beach [5]",
  "Beach [6]",
  "Beach [7]",
  "Beach [8]",
  "Beach [9]",
  "Amalgus Bean Plantation",
  "Beeldeban Herder",
  "Beeldeban Nest",
  "Black Hole Generator",
  "Bread Bakery",
  "Malcud Burger Packer",
  "Capitol",
  "Cheese Maker",
  "Denton Root Chip Frier",
  "Apple Cider Bottler",
  "Citadel of Knope",
  "Cloaking Lab",
  "Corn Plantation",
  "Corn Meal Grinder",
  "Crashed Ship Site",
  "Crater",
  "Culinary Institute",
  "Dairy Farm",
  "Denton Root Patch",
  "Denton Brambles",
  "Deployed Bleeder",
  "Development Ministry",
  "Distribution Center",
  "Embassy",
  "Energy Reserve",
  "Entertainment District",
  "Espionage Ministry",
  "Essentia Vein",
  "Fission Reactor",
  "Fissure",
  "Food Reserve",
  "Fusion Reactor",
  "Gas Giant Lab",
  "Gas Giant Settlement Platform",
  "Genetics Lab",
  "Geo Energy Plant",
  "Geo Thermal Vent",
  "Gratch's Gauntlet",
  "Great Ball of Junk",
  "Grove of Trees",
  "Halls of Vrbansk",
  "Hydrocarbon Energy Plant",
  "Interstellar Broadcast System",
  "Intel Training",
  "Intelligence Ministry",
  "Interdimensional Rift",
  "Junk Henge Sculpture",
  "Kalavian Ruins",
  "Kastern's Keep",
  "Lost City of Tyleon (A)",
  "Lost City of Tyleon (B)",
  "Lost City of Tyleon (C)",
  "Lost City of Tyleon (D)",
  "Lost City of Tyleon (E)",
  "Lost City of Tyleon (F)",
  "Lost City of Tyleon (G)",
  "Lost City of Tyleon (H)",
  "Lost City of Tyleon (I)",
  "Lagoon",
  "Lake",
  "Lapis Orchard",
  "Lapis Forest",
  "Library of Jith",
  "Luxury Housing",
  "Malcud Fungus Farm",
  "Malcud Field",
  "Massad's Henge",
  "Mayhem Training",
  "Mercenaries Guild",
  "Metal Junk Arches",
  "Mine",
  "Mining Ministry",
  "Mission Command",
  "Munitions Lab",
  "Natural Spring",
  "Network 19 Affiliate",
  "Observatory",
  "Opera House",
  "Oracle of Anid",
  "Ore Refinery",
  "Ore Storage Tanks",
  "Oversight Ministry",
  "Potato Pancake Factory",
  "Pantheon of Hagness",
  "Park",
  "Parliament",
  "Lapis Pie Bakery",
  "Pilot Training Facility",
  "Planetary Command Center",
  "Police Station",
  "Politics Training",
  "Potato Pancake Factory",
  "Propulsion System Factory",
  "Pyramid Junk Sculpture",
  "Ravine",
  "Rocky Outcropping",
  "Shield Against Weapons",
  "Space Station Lab (A)",
  "Space Station Lab (B)",
  "Space Station Lab (C)",
  "Space Station Lab (D)",
  "Patch of Sand",
  "Security Ministry",
  "Beeldeban Protein Shake Factory",
  "Shipyard",
  "Singularity Energy Plant",
  "Amalgus Bean Soup Cannery",
  "Space Junk Park",
  "Space Port",
  "Station Command Center",
  "Stockpile",
  "Subspace Supply Depot",
  "Supply Pod",
  "Algae Syrup Bottler",
  "Temple of the Drajilites",
  "Terraforming Lab",
  "Terraforming Platform",
  "The Dillon Forge",
  "Theft Training",
  "Theme Park",
  "Trade Ministry",
  "Subspace Transporter",
  "University",
  "Volcano",
  "Warehouse",
  "Waste Digester",
  "Waste Energy Plant",
  "Waste Exchanger",
  "Waste Recycling Center",
  "Waste Sequestration Well",
  "Waste Treatment Center",
  "Water Production Plant",
  "Water Purification Plant",
  "Water Reclamation Facility",
  "Water Storage Tank",
  "Wheat Farm",
  ];
  return $bld_names;
}