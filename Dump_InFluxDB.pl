#!/usr/bin/perl -w

# part of perl script <Dump_InFluxDB.pl>
# Copyright (C) 2020  Stefan Eichenberger
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# An original version of the GNU General Public Licence can be found
# here: <https://www.gnu.org/licenses/>.

# ---------------------------------------------------------------------------------------
# Revision History
# ================
#   1.00.00    2020-05-17       Initial release
#   1.00.01    2020-05-25       Minor bug-fixes
#                                 - multiple tabs were not created correctly
#                                 - date intervals without data created tun-time errors
#                                 - proper date/time format for DateTime
# ---------------------------------------------------------------------------------------
our $VERSION = "1.01.00, 2021-08-07";

use strict;

BEGIN {
  use DirHandle;
  my($cwd, $me, $dirH, $fname, $path, @DIRS);
  
  $me = $0;
  $me =~ s/\\/\//g;                    # Windows uses '\', Unix uses '/'
  $me =~ /^(.*?)([^\/]+)$/;            # make sure we find other modules local to 'dataViewer.pl'
  $cwd = $1;
  $me  = $2;
  unless ($cwd) { $cwd = "./"; }
  unshift (@INC, $cwd);
}

use DateTime;
use Getopt::Std;
use IO::Handle;
use Excel::Writer::XLSX;
use Dump_InFluxDB::Config;
use Dump_InFluxDB::Dump;

my $YEAR       =  5;                                                            # fields in localtime()
my $MONTH      =  4;                                                            # see https://perldoc.perl.org/functions/localtime.html
my $DAY        =  3;
my $FORCE_DAYS = 32;                                                            # for longer periods, request -f 
#             NA   1   2   3   4   5   6   7   8   9  10  11  12
my @MAX_DAY = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);

my(%args, @now, @period, $cfg, $dump, $where, $duration, $elapsed,
   $f_year, $f_month, $f_day,                                                   # from y/m/d
   $t_year, $t_month, $t_day);                                                  # to   y/m/d

$elapsed = time();
print "Dump_InFluxDB started at " .gmtime() . " ...\n";

# ------------------------------------------------------------------------------  command line processing
@now     = gmtime();                                                            # default month is current month
$f_year  = $now[$YEAR]  + 1900;
$f_month = $now[$MONTH] + 1;
$f_day   = 1;

$t_year  = $now[$YEAR]  + 1900;
$t_month = $now[$MONTH] + 1;

$args{y} = $f_year;
$args{m} = $f_month;
$args{d} = $f_day;
$args{c} = 'config.ini';

getopts('y:m:d:Y:M:D:c:T:O:ofvh', \%args);

if ($args{h}) { &help(); }                                                      # print help and exit

if ($args{d} > 0) {
  $f_year  = $args{y};
  $f_month = $args{m};
  $f_day   = $args{d};
} else {
  $f_day   = $now[$DAY];
} 

$t_year  = $args{Y} || $f_year;
$t_month = $args{M} || $f_month;
if ($now[$MONTH]+1 == $t_month) {
  $t_day = $now[$DAY];
} else {
  $t_day   = $MAX_DAY[$t_month];
  if ($t_year % 4 == 0 && $t_month == 2) { $t_day++; }                          # correct leap year
}
$t_day   = $args{D} || $t_day;

$period[0] = DateTime->new(year   => $f_year,
                           month  => $f_month,
                           day    => $f_day,
                           hour   => 0,
                           minute => 0,
                           second => 0);
if ($args{d} < 0) {
  $duration = DateTime::Duration->new(days => $args{d}+1);
  $period[0]->add_duration($duration);
}

$period[1] = DateTime->new(year   => $t_year,
                           month  => $t_month,
                           day    => $t_day,
                           hour   => 23,
                           minute => 59,
                           second => 59);

if ($period[0] > $period[1]) {
  die "ERROR --- start date $period[0] is later than end date $period[1]\n";
}
$where    = sprintf ("time >= '$period[0]Z' and time <= '$period[1]Z'");
$duration = $period[1] - $period[0];
if (!$args{f} && $duration->{days} > $FORCE_DAYS) {
  $where =~ s/T[0-9:]+Z//g;
  $where =~ s/'//g;
  $where =~ s/time/Date/g;
  die "ERROR --- more than $FORCE_DAYS requested with $where; use -f to force output\n";
}

$cfg   = Dump_InFluxDB::Config->new($args{c});
if ($cfg) {
  print "  -- using config file $args{c}\n";
}

$dump  = Dump_InFluxDB::Dump->new($cfg, \%args, $where);
$dump->openXLSX($period[0]);                                                    # open early, so that we get error handling early
print "  -- timespan: $where\n";

$dump->getTables();                                                             # get InFlux tables
$dump->writeXLSX($period[0]);                                                    # dump to XLSX
$elapsed = time() - $elapsed;
print "Dump_InFluxDB terminated at " . gmtime() . ", elapsed: $elapsed" . "s\n";

sub help {
  print "\n\nUsage:\n" .
        "    Dump_InFluxDB.pl [<time_period_options> -f -o -T <list> -c <CfgFile> -v]\n" .
        "        dumps data from InFlux DB into an .xlsx file\n\n" .
        "        Time period of dump is defined through <time_period_options>:\n" .
        "            Default: current month from yyyy-mm-01 to YYYY-MM-DD (DD = last day of month)\n" .
        "            Parts can be overwritten:\n" .
        "            -d <d>     overwrites start date day\n" .
        "                       If <d> is negative, start date is set to <today> - <d> days\n" . 
        "                       Example: -d -1 dumps today only, -d -10 dumps last 10 days incl. today\n" .
        "            -m <m>, -y <y> overrites month mm and year  yy of start date (neglected if <d> < 0)\n" .
        "            -D <d>, -M <m>, -Y <y> overwrites day DD, month MM, year YYYY of end date\n" .
        "            Time is from 00:00 to 23:59 UTC of the respective start and end dates\n\n" .
        "        For long periods, memory consumption may become huge (and performance slow). Hence,\n" .
        "        period cannot be longer than 32 days unless -f forces a protection overwrite.\n" .
        "        This is done at the users risk and may crash Influx and/or the Raspi due to memory\n" .
        "        consumption\n\n" .
        "        -o  allow overwriting if output file already exists (default: no overwrite)\n" .
        "        -O  <OutFile> creates output file <file_yyyy-mm-dd.xlsx> where yyyy-mm-dd is the start\n" .
        "                      day of the dumped time period. Default 'SolarAnzeige'\n" .
        "        -T  <list>    <list> is a comma-separated list of tabs to be created\n" .
        "                     Default: all tabs\n" .
        "        -c  <CfgFile> Config file; default: config.ini\n" .
        "        -v  verbose output (for chart debugging)\n\n" .
        "    Dump_InFluxDB.pl -h\n" .
        "        --> shows this help text\n\n" .
        "    Version: $VERSION, Stefan Eichenberger\n\n";
  exit;
}