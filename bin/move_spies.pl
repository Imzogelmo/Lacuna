#!/usr/bin/env perl
#
# Script for sending and fetching spies.
# Will use spaceport method as default which is cheaper RPC wise, but
# can only send/fetch 100 spies at most.  If intel method is used, as many
# spies as can fit in a ship can be moved.
# Can use planet names if they exist in probe_data_cmb.js
# or you can use body_id if known.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use List::Util            (qw(first));
use Getopt::Long          (qw(GetOptions));
use Games::Lacuna::Client ();
use File::Copy;
use DateTime;
use Date::Parse;
use Date::Format;
use JSON;
use utf8;

  my $random_bit = int rand 9999;
  my $data_dir = 'data';
  my $log_dir  = 'log';

  my %opts = (
    h            => 0,
    v            => 0,
    config       => "lacuna.yml",
    probefile    => "data/probe_data_cmb.js",
    dumpfile     => $log_dir . '/spy_move_'.
                      time2str('%Y%m%dT%H%M%S%z', time).
                      "_$random_bit.js",
    min_def  => 0,
    min_off  => 0,
    max_def  => 10000,
    max_off  => 10000,
    min_intel  => 0,
    max_intel  => 10000,
    min_mayhem  => 0,
    max_mayhem  => 10000,
    min_politics  => 0,
    max_politics  => 10000,
    min_theft  => 0,
    max_theft  => 10000,
  );

  GetOptions(\%opts,
    'config=s',
    'dumpfile=s',
    'dryrun',
    'aname=s',
    'h|help',
    'number=i',
    'probefile=s',
    'from=s',
    'to=s',
    'id',
    'intel',
    'fetch',
    'sname=s',
    'stype=s',
    'min_def=i',
    'min_off=i',
    'max_def=i',
    'max_off=i',
    'min_intel=i',
    'max_intel=i',
    'min_mayhem=i',
    'max_mayhem=i',
    'min_politics=i',
    'max_politics=i',
    'min_theft=i',
    'max_theft=i',
    'v|verbose',
  );
  
  my $glc = Games::Lacuna::Client->new(
    cfg_file => $opts{config},
    rpc_sleep => 2,
    prompt_captcha => 1,
    # debug    => 1,
  );

  usage() if $opts{h};
  usage() unless $opts{from} and $opts{to};

  die "dump already exists" if ( -e $opts{dumpfile} );

  my $df;
  open($df, ">", "$opts{dumpfile}") or die "Could not open $opts{dumpfile}\n";

  my $json = JSON->new->utf8(1);
  my $pdata;
  unless ($opts{id}) { # No need to read probe data file
    if (-e $opts{probefile}) {
      print "Reading probefile\n";
      my $pf; my $lines;
      open($pf, "$opts{probefile}") || die "Could not open $opts{probefile}\n";
      $lines = join("", <$pf>);
      $pdata = $json->decode($lines);
      close($pf);
    }
    else {
      print "Could not read $opts{probefile}\n";
    }
  }

# Load the planets
  my $status  = $glc->empire->get_status();
  my $empire  = $status->{empire};

  my $rpc_cnt_beg = $glc->{rpc_count};
  print "RPC Count of $rpc_cnt_beg\n";

  my $from_id; my $from_own; my $from_name;
  my $to_id;   my $to_own;   my $to_name;
  if ($opts{id}) {
    $from_id = $opts{from};
    $to_id   = $opts{to};
    ($from_name, $from_own) = get_pname($from_id, $empire);
    ($to_name,   $to_own)   = get_pname($to_id,   $empire);
  }
  else {
    $from_name = $opts{from};
    $to_name   = $opts{to};
    ($from_id, $from_own) = get_id("$from_name", $pdata);
    ($to_id,   $to_own)   = get_id("$to_name",   $pdata);
    if ($from_id == 0 or $to_id == 0) {
      die "$opts{from} : $from_id or $opts{to} : $to_id invalid\n";
    }
  }
  undef $pdata; #Dump from memory
# Determine if we are sending or fetching
  my $spy_planet_id;
  my $spy_planet_name;
  my $dirstr;
  my $send;
  if ( $opts{fetch} ) {
    die "Must own $from_name to be able to send from!\n" unless ($from_own);
    $spy_planet_id = $to_id;
    $spy_planet_name = $to_name;
    $send = 0;
    $dirstr = "Fetching";
  }
  elsif ($from_own) {
    $spy_planet_id = $from_id;
    $spy_planet_name = $from_name;
    $send = 1;
    $dirstr = "Sending";
  }
  elsif ($to_own) {
    $spy_planet_id = $to_id;
    $spy_planet_name = $to_name;
    $send = 0;
    $dirstr = "Fetching";
  }
  else {
    die "Could not figure out send/fetch syntax!\n";
  }

  my @spies;
  my @ships;

  printf "Sending from %s:%s:%s to %s:%s:%s\n", $from_id, $from_name,$from_own,$to_id,$to_name,$to_own;
  print "Getting spy and ship ids from $spy_planet_name\n";

  my ($space_port, $intel) = get_bld_pnt($spy_planet_id, $spy_planet_name, $opts{intel});

#  print "Getting spy and ship ids from $spy_planet_name\n";

  my $prep;
  my $ok = eval {
    if ($send) {
      $prep = $space_port->prepare_send_spies( $from_id, $to_id);
    }
    else {
      $prep = $space_port->prepare_fetch_spies( $from_id, $to_id);
    }
  };
  unless ($ok) {
    my $error = $@;
    die $error,"\n";
  }

  @ships = @{$prep->{ships}};
  unless (@ships) {
    die "No ships available from $spy_planet_name!\n";
  }

  if ($opts{intel}) {
    @spies = get_spies_intel($intel);
    print scalar @spies, " spies found based out of $spy_planet_name.\n";
    @spies = grep { lc ($_->{assigned_to}{name}) eq lc($from_name) } @spies;
    print scalar @spies, " spies on $from_name.\n";
    @spies = grep { $_->{is_available} } @spies;
    print scalar @spies, " spies available.\n";
  }
  else {
    @spies = @{$prep->{spies}};
    print scalar @spies, " spies found available from $from_name.\n";
  }
  unless (@spies) {
    die "No spies to $dirstr!\n";
  }
  if ($opts{aname}) {
    @spies = grep { $_->{name} =~ /^$opts{aname}/i } @spies;
  }

  my @spy_ids = map { $_->{id} }
                grep { $_->{offense_rating} >= $opts{min_off} and
                       $_->{offense_rating} <= $opts{max_off} and
                       $_->{defense_rating} >= $opts{min_def} and
                       $_->{defense_rating} <= $opts{max_def} and
                       $_->{intel} >= $opts{min_intel} and
                       $_->{intel} <= $opts{max_intel} and
                       $_->{mayhem} >= $opts{min_mayhem} and
                       $_->{mayhem} <= $opts{max_mayhem} and
                       $_->{politics} >= $opts{min_politics} and
                       $_->{politics} <= $opts{max_politics} and
                       $_->{theft} >= $opts{min_theft} and
                       $_->{theft} <= $opts{max_theft}
                     } @spies;

  @spy_ids = sort { $a <=> $b } @spy_ids;

  if ($opts{number} and $opts{number} < scalar @spy_ids) {
    print "$dirstr $opts{number} of ",scalar @spies, " spies.\n";
    splice @spy_ids, $opts{number};
  }
  else {
    print $dirstr," ",scalar @spy_ids, " of ", scalar @spies, " spies.\n";
  }

  if ($opts{sname}) {
    @ships = grep { $_->{name} =~ /$opts{sname}/i } @ships;
  }
  if ($opts{stype}) {
    @ships = grep { $_->{type} =~ /$opts{stype}/i } @ships;
  }

  my $ship = List::Util::first { $_->{max_occupants} >= scalar @spy_ids }
                  sort {$b->{speed} <=> $a->{speed} } @ships;

  my %dumpfile;
  $dumpfile{spies} = \@spy_ids;
  $dumpfile{ships} = $ship;

  unless ($ship) {
    print "No suitable ship found!\n";
  }
  else {
    print $dirstr, " ",scalar @spy_ids," from $from_name to $to_name using ",
        $ship->{name}, "\n";
    unless ($opts{dryrun}) {
      my $sent;
      my $ok = eval {
        if ($send) {
          $sent = $space_port->send_spies( $from_id, $to_id, $ship->{id}, \@spy_ids);
        }
        else {
          $sent = $space_port->fetch_spies( $from_id, $to_id, $ship->{id}, \@spy_ids);
        }
      };

      if ($ok) {
        if ($send) { print "Spies sent"; } else { print "Spies fetched"; }
        print ", arriving ", $sent->{ship}->{date_arrives},"\n";
      }
      else {
        my $error = $@;
        print $error,"\n";
      }
    }
    else {
      print "Dryrun, no spies actually moved.\n";
    }
  }
  
  print $df $json->pretty->canonical->encode(\%dumpfile);
  close $df;
  my $rpc_cnt_end = $glc->{rpc_count};
  print "RPC Count of $rpc_cnt_end\n";
exit;


sub get_spies_intel {
  my ($intel) = @_;

  my ($page, $done);
  while(!$done) {
    my $spies = $intel->view_spies(++$page);
    push @spies, @{$spies->{spies}};
    $done = 25 * $page >= $spies->{spy_count};
  }

  return @spies;
}

sub get_bld_pnt {
  my ($planet_id, $pname, $intel_fl) = @_;

  my $planet    = $glc->body( id => $planet_id );
  my $result    = $planet->get_buildings;
  my $buildings = $result->{buildings};

  my $space_port_id = List::Util::first {
          $buildings->{$_}->{url} eq '/spaceport'
  }
  grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
  keys %$buildings;

  die "No space port found on $pname\n" unless $space_port_id;
  my $space_port = $glc->building( id => $space_port_id, type => 'SpacePort' );

  my $intel = 0;
  if ($intel_fl) {
    my $intel_id = List::Util::first {
          $buildings->{$_}->{url} eq '/intelligence'
    }
    grep { $buildings->{$_}->{level} > 0 and $buildings->{$_}->{efficiency} == 100 }
    keys %$buildings;

    die "No intelligence ministry found on $from_name\n" unless $intel_id;

    $intel      = $glc->building( id => $intel_id, type => 'Intelligence' );
  }
  return $space_port, $intel;
}

sub get_id {
  my ($name, $pdata) = @_;

  for my $bod (@$pdata) {
    next if ($bod->{name} ne "$name");
    print "Found $name as $bod->{id} ";
    my $self = 0;
    if (defined($bod->{empire}) and $bod->{empire}->{alignment} eq "self") {
      $self = 1;
      print "and is self.\n";
    }
    else {
      print "and is foreign.\n";
    }
    return ( $bod->{id}, $self);
  }
  print "Could not find ID for $name\n";
  return (0, 0);
}

sub get_pname {
  my ($pid, $empire) = @_;

  if (defined($empire->{planets}->{$pid})) {
    return ("$empire->{planets}->{$pid}", 1);
  }
  return ($pid, 0);
}

sub usage {
    diag(<<END);
Usage: $0 --from <planet> --to <planet>

Options:
  --help                 - Prints this out
  --config    cfg_file   - Config file, defaults to lacuna.yml
  --verbose              - Print more details.
  --dumpfile  dump_file  - Where to dump json
  --dryrun               - Just setup, but don't actually send or fetch
  --number    integer    - Number of agents to fetch or send
  --probefile probe_file - Default data/probe_data_cmb.js
  --from      Planet     - Planet Name that spies will travel from
  --to        Planet     - Planet Name that spies will travel to
  --intel                - Use Int Ministry to determine which spies
  --id                   - Use Planet IDs for targeting.
  --send                 - Use send method if possible, fetch is default
  --sname     Ship Name  - Name of ship to use, partial works
  --stype     Ship Type  - Type of ship to use, partial works
  --min_def   integer    - Minimum Defense of agents to transport
  --min_off   integer    - Minimum Offense of agents to transport
  --max_def   integer    - Maximum Defense of agents to transport
  --max_off   integer    - Maximum Offense of agents to transport
END
 exit 1;
}

sub diag {
    my ($msg) = @_;
    print STDERR $msg;
}
