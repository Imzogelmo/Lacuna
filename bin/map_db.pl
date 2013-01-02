#!/usr/bin/env perl
# Hacked from Steffen's code and then some of cxreg's stuffed in
use strict;
use warnings;

use feature ':5.10';

use DBI;
use Data::Dumper;
use Imager;
use Getopt::Long qw(GetOptions);
use JSON;
use Text::CSV;

  my $imgfile = "map_db.png";
  my $map_file = 'data/map_empire.js';
  my $dbfile = 'data/stars.db';
  my $starfile = 'data/stars.csv';
  my $share = 0; # If share, we strip out color coding occupied planets
  my $showstars = 0; # If show_stars, we put in non-probed stars
  my $excavate = 0; # If excavate, special color for excavated bodies
  my $blur = 0; # Spread colors a bit

  GetOptions(
    'empire_file=s' => \$map_file,
    'database=s' => \$dbfile,
    'starfile=s' => \$starfile, # We could get this out of database
    'share' => \$share,
    'showstars' => \$showstars,
    'excavate' => \$excavate,
    'blur'     => \$blur,
  );

  my $json = JSON->new->utf8(1);
  my $config;
  if (-e $map_file) {
    my $map_f; my $lines;
    open($map_f, "$map_file") || die "Could not open $map_file\n";
    $lines = join("", <$map_f>);
    $config = $json->decode($lines);
    close($map_f);
  }

  my $my_empire_id = $config->{empire_id} || '';
  unless ( $my_empire_id ) {
    die "empire_id missing from $map_file\n";
  }

  my @allied_empires = @{ $config->{allied_empires} };
  unless ( @allied_empires ) {
    warn "No allied_empires found.\n";
  }
  my %allied_empires = map {($_ => 1)} @allied_empires;

  my $db = DBI->connect("dbi:SQLite:$dbfile")
    or die "Can't open SQLite db $dbfile: $DBI::errstr\n";
  $db->{ReadOnly} = 1;
  $db->{RaiseError} = 1;
  $db->{PrintError} = 0;

# die "fix SQL statement";
my $sql = <<SQL;
select body_id, o.name as o_name, orbit, o.x as x, o.y as y, o.type as type,
       star_id, empire_id, s.x as s_x, s.y as s_y, s.color as color, last_excavated
from orbitals o join stars s on o.star_id = s.id
SQL

  my $get = $db->prepare($sql);
  $get->execute();

  my $stars;
  if (-e $starfile) {
    $stars = get_stars("$starfile");
  }
  else {
    die "No stars file: $starfile\n";
  }

  my $min_x = $config->{min_x};
  my $max_x = $config->{max_x};
  my $min_y = $config->{min_y};
  my $max_y = $config->{max_y};

  my $xborder = 21;
  my $yborder = 21;
  my ($map_xsize, $map_ysize) = ($max_x - $min_x + 1, $max_y - $min_y + 1);
  my ($xsize, $ysize) = ($map_xsize+$xborder, $map_ysize+$yborder);

  my $img = Imager->new(xsize => $xsize+$xborder, ysize => $ysize+$yborder);
  my $black  = Imager::Color->new(  0,   0,   0);
  my $dull   = Imager::Color->new( 40,  40,  40);
  my $blue   = Imager::Color->new(  0,   0, 255);
  my $cyan   = Imager::Color->new(  0, 255, 255);
  my $green  = Imager::Color->new(  0, 255,   0);
  my $grey   = Imager::Color->new( 80,  80,  80);
  my $magenta= Imager::Color->new(255,   0, 255);
  my $purple = Imager::Color->new( 80,   0,  80);
  my $red    = Imager::Color->new(255,   0,   0);
  my $silver = Imager::Color->new(192, 192, 192);
  my $yellow = Imager::Color->new(255, 255,   0);
  my $white  = Imager::Color->new(255, 255, 255);
  $img->box(filled => 1, color => $black);

  $img->line(x1 => $map_xsize+1, x2 => $map_xsize+1,
             y1 => 1, y2 => $map_ysize+1, color => $white);
  $img->line(x1 => 1, x2 => $map_xsize+1,
             y1 => $map_ysize+1, y2 => $map_ysize+1, color => $white);

  use Imager::Fill;
  my $fill1 = Imager::Fill->new(solid=>$green);
  $img->box(xmin => $map_xsize+9, xmax => $map_xsize+13,
          ymin => int($map_ysize/4.), ymax => int($map_ysize*3/4),
          color => $green, fill => $fill1);
  $img->polygon(
    color => $green, fill => $fill1,
    points => [
      [$map_xsize+11, int($map_ysize*1/4.)-4],
      [$map_xsize+11-9, int($map_ysize*1/4.)+15],
      [$map_xsize+11+9, int($map_ysize*1/4.)+15],
    ],
  );

  $img->box(xmin => int($map_xsize/4.), xmax => int($map_xsize*3/4),
            ymin => $map_ysize+10, ymax => $map_ysize+12,
            color => $green, fill => $fill1);
  $img->polygon(
    color => $green, fill => $fill1,
    points => [
      [int($map_xsize*3/4.)+4, $map_ysize+11],
      [int($map_xsize*3/4.)-15, $map_ysize+11-9],
      [int($map_xsize*3/4.)-15, $map_ysize+11+9],
    ],
  );

  if ($showstars) {
    for my $star_id (keys %{$stars}) {
      $img->setpixel(x => $stars->{"$star_id"}->{x} - $min_x,
                     y => $map_ysize-($stars->{"$star_id"}->{y} - $min_y),
                     color => $stars->{"$star_id"}->{color});
    }   
  }

  my $offset = get_offset();

  my $color;
  my $ecount = 0;
  my $acount = 0;
  my $hcount = 0;
  my $gcount = 0;
  my $ocount = 0;
  my $ucount = 0;
  my $scount = 0;
  while (my $bod = $get->fetchrow_hashref) {
    if (!defined($bod->{type})) {
      $color = $red;
      $ocount++;
    }
    elsif ($excavate and (defined($bod->{last_excavated}) and $bod->{last_excavated} ne '')) {
      $color = $blue;
      $ecount++;
    }
    elsif ($bod->{type} eq "asteroid") {
      $color = $silver;
      $acount++;
    }
    elsif ($bod->{type} eq "gas giant") {
      $color = $cyan;
      $gcount++;
    }
    elsif ($bod->{type} eq "habitable planet") {
      $color = $green;
      $hcount++;
    }
    elsif ($bod->{type} eq "space station") {
      $color = $blue;
      $scount++;
    }
    elsif ($bod->{type} eq "empty") {
      $color = $black;
    }
    else {
      $color = $magenta;
      $ucount++;
    }
    if (!$share and defined($bod->{empire_id})) {
      $color = $red;
      $ocount++;
    }
    $img->setpixel(x => $bod->{x} - $min_x,
                   y => $map_ysize-($bod->{y} - $min_y),
                   color => $color);
    if ($blur) {
      for my $pnt (0..4) {
        $img->setpixel(x => $bod->{x} - $min_x
                            + $offset->[$bod->{orbit}]->[$pnt]->{x},
                     y => $map_ysize - ($bod->{y} - $min_y)
                            + $offset->[$bod->{orbit}]->[$pnt]->{y},
                     color => $color);
      }
      
    }
    $img->setpixel(x => $stars->{"$bod->{star_id}"}->{x} - $min_x,
                   y => $map_ysize-($stars->{"$bod->{star_id}"}->{y} - $min_y),
                   color => $stars->{"$bod->{star_id}"}->{color});
  }
  printf "H:%5d, A:%5d, G:%5d, O:%5d, S:%5d, U:%5d, E: %5d\n",
          $hcount, $acount, $gcount, $ocount, $scount, $ucount, $ecount;

  $img->write(file => "$imgfile")
    or die q{Cannot save $imgfile, }, $img->errstr;


exit;

sub get_stars {
  my ($sfile) = @_;

  my $fh;
  open ($fh, "<", "$sfile") or die;

  my $fline = <$fh>;
  my %star_hash;
  while(<$fh>) {
    chomp;
    my ($id, $name, $x, $y, $color, $zone) = split(/,/, $_, 6);
    $star_hash{$id} = {
      id    => $id,
      name  => $name,
      x     => $x,
      y     => $y,
      color => $color,
      zone  => $zone,
    }
  }
  return \%star_hash;
}

sub get_offset {
  my $array = [
    [ { x =>  0, y=>  0 },
      { x =>  0, y=>  0 },
      { x =>  0, y=>  0 },
      { x =>  0, y=>  0 },
      { x =>  0, y=>  0 }, ],
    [ { x => -1, y=>  0 },
      { x => -1, y=> -1 },
      { x =>  0, y=> -1 },
      { x =>  1, y=> -1 },
      { x => -1, y=>  1 }, ],
    [ { x => -1, y=>  0 },
      { x =>  1, y=>  0 },
      { x =>  1, y=> -1 },
      { x =>  1, y=> -2 },
      { x =>  0, y=> -1 }, ],
    [ { x =>  0, y=> -1 },
      { x =>  1, y=>  0 },
      { x =>  1, y=>  1 },
      { x =>  1, y=> -1 },
      { x => -1, y=> -1 }, ],
    [ { x =>  1, y=>  0 },
      { x =>  0, y=>  1 },
      { x =>  1, y=>  1 },
      { x =>  2, y=>  1 },
      { x =>  0, y=> -1 }, ],
    [ { x =>  1, y=>  0 },
      { x =>  0, y=>  1 },
      { x => -1, y=>  1 },
      { x =>  1, y=>  1 },
      { x =>  1, y=> -1 }, ],
    [ { x =>  1, y=>  0 },
      { x => -1, y=>  0 },
      { x => -1, y=>  1 },
      { x => -1, y=>  2 },
      { x =>  0, y=>  1 }, ],
    [ { x =>  0, y=>  1 },
      { x => -1, y=> -1 },
      { x => -1, y=>  0 },
      { x => -1, y=>  1 },
      { x =>  1, y=>  1 }, ],
    [ { x =>  0, y=>  1 },
      { x =>  0, y=> -1 },
      { x => -1, y=> -1 },
      { x => -2, y=> -1 },
      { x => -1, y=>  0 }, ],
  ];

  return $array;
}
