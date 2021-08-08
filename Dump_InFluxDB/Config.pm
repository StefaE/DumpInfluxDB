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

package Dump_InFluxDB::Config;

use strict;
use Cwd;

my(%mandatory, %dbmodel, %defaults);

%mandatory = (                      # mandatory data items (per section) in config file
             );

sub new {
  my($self, $cfgFile, $vars) = @_;
 
  unless (defined($vars)) { $vars = []; }
  $self = bless { sections => {},
                  general  => {},
                  cfgFile  => $cfgFile,
                  path     => cwd(),
                  vars     => $vars
                }, $self;
  
  $self->_readConfig($cfgFile);
  ${$self->{general}}{dbmodel} = \%dbmodel; 
  return $self; 
}

sub getSections {
  # returns pointer to array containing all section names
  my($self) = @_;
  my(@sections);
  
  @sections = sort keys %{$self->{sections}};
  return \@sections;
}

sub hasSection { exists($_[0]->{sections}->{$_[1]}); }

sub clearSections {
  my($self) = @_;
  foreach my $section (keys %{$self->{sections}}) {
    if ($section ne 'GENERAL') {
      delete ${$self->{sections}}{$section};
    }
  }
}

sub getConfig {
  my($self, $key, $section, $isFile) = @_;
  my($cfg, $host, $inherit, @fields, $field, $found, @map, $listPtr, $mySection);
  
  $cfg = '';
  if ($key eq 'DATABASE') {
    $key  = 'database';
    $host = 0;
  } else { $host = 1; }
  if ($section) {
    if (exists(${$self->{sections}}{$section}) &&
        exists(${${$self->{sections}}{$section}}{$key})) {
      $cfg = ${${$self->{sections}}{$section}}{$key};
    }
  } else { $section = ''; }
  if (($cfg eq '') && (exists(${$self->{general}}{$key}))) {
    $cfg = ${$self->{general}}{$key};
    if ($cfg =~ /==>/) {
      (@map) = split /(?<!\\);/, $cfg;
      $listPtr = $self->_mapResolve(\@map, '==>');
      $cfg = $listPtr->{$ENV{LOGONSERVER}};
      unless ($cfg) { $cfg = $listPtr->{else}; }
    }
  }
  if (($key eq 'database') && ($host)) {
    $host = $self->getConfig('host', $section);
    if ($host) { $cfg .= ";host=$host" }
  }
  if (($cfg eq '') && exists($defaults{$key})) { $cfg = $defaults{$key}; }
  if ($isFile && $cfg !~ /^\//) {
    $cfg = $self->{path} . '/' . $cfg;
  } elsif ((!$cfg) && exists(${$self->{sections}}{$section}) &&
                      exists(${${$self->{sections}}{$section}}{inherit})) {
    $inherit = ${${$self->{sections}}{$section}}{inherit};
    $mySection = $section;
    ($section, @fields) = split /[\/;\|]/, $inherit;
    if ($section eq $mySection) {
        die "ERROR   --- Config of section $section tries inherit from itself; aborted\n";
    }
    $found = 0;
    foreach $field (@fields) {
      if (($field eq 'all') || ($field =~ /^\s*$key\s*$/)) { $found = 1; }
      if ($field =~ /^\s*-$key\s*$/) { $found = 0; }
    }
    if ($found) { $cfg = $self->getConfig($key, $section); }
  }
  if ($cfg =~ /\$v/) {
    foreach my $v (@{$self->{vars}}) {
      if ($v) { $cfg =~ s/\$v/$v/; }
    }
  }
  return $cfg;
}

sub putConfig {
  my ($self, $key, $section, $value) = @_;
  if ($section eq 'GENERAL') {
    ${$self->{general}}{$key} = $value;
  } else {
    ${${$self->{sections}}{$section}}{$key} = $value;
  }
}

sub merge {
  my($self, $to, $from, $what) = @_;
  my($fromHash, $toHash, $toVal, $fromVal, $str, %seen);
  
  if ($from eq 'GENERAL') {
    $fromHash = $self->{general};
  } else {
    $fromHash = ${$self->{sections}}{$from};
  }
  if ($to eq 'GENERAL') {
    $toHash = $self->{general};
  } else {
    $toHash = ${$self->{sections}}{$to};
  }
  foreach my $key (keys %$fromHash) {
    if (($what =~ /[\/;\|]all[\/;\|]/ || $what =~ /[\/;\|]$key[\/;\|]/) && $what !~ /[\/;\|]-$key[\/;\|]/) {
      $fromVal = $self->getConfig($key, $from);
      if ($fromVal =~ /=>/) {
        $fromVal = $self->getConfigMap($key, $from);
        $toVal   = $self->getConfigMap($key, $to);
        foreach my $key2 (keys %$fromVal) {
          ${$toVal}{$key2} = ${$fromVal}{$key2};
        }
        $str = '';
        foreach my $key2 (keys %$toVal) {
          $str .= "$key2 => ${$toVal}{$key2};";
        }
        $self->putConfig($key, $to, $str);
      } elsif ($fromVal =~ /;/) {
        $fromVal = $self->getConfigList($key, $from);
        $toVal   = $self->getConfigList($key, $to);
        $str = '';
        undef %seen;
        foreach my $val (@$fromVal) {
          $str .= "$val;";
          $seen{$val} = 1;
        }
        foreach my $val (@$toVal) {
          unless ($seen{$val}) { $str .= "$val;"; }
        }
        $self->putConfig($key, $to, $str);
      } else {
        $self->putConfig($key, $to, $self->getConfig($key, $from));
      }
    }
  }
}

sub substitue {
  my($self, $to, $from) = @_;
  my($fromHash, $fromVal);
  
  if ($from eq 'GENERAL') {
    $fromHash = $self->{general};
  } else {
    $fromHash = ${$self->{sections}}{$from};
  }
  foreach my $key (keys %$fromHash) {
    $fromVal = $self->getConfig($key, $from);
    $self->putConfig($key, $to, $self->getConfig($key, $from));
  }
}

sub mergeFrom {
  my($self) = @_;
  my($from, $what);
  foreach my $section (@{$self->getSections}) {
    if ($from = $self->getConfig('mergeFrom', $section)) {
      if ($from =~ /^([^\/;\|]+)([\/;\|].+)$/) {
        $from = $1;
        $what = $2;
      } else {
        $what = '/all/';
      }
      $self->merge($section, $from, $what);
    }
  }
}

sub getConfigMap {
  my($self, $cfgKey, $section) = @_;
  my(@map, $listPtr);
  
  (@map) = split /(?<!\\);/, $self->getConfig($cfgKey, $section);
  $listPtr = $self->_mapResolve(\@map);
  return $listPtr;
}

sub _mapResolve {
  my($self, $mapPtr, $split) = @_;
  my($mapElem, $key, $val, %list);
  
  if (!$split) { $split = '=>'; }
  foreach $mapElem (@$mapPtr) {
    if ($mapElem =~ /^\s*(.+?)\s*=>\s*(.*?)\s*$/) {
      $key = $1;
      $val = $2;
    } else {
      $key = $mapElem;
      $key =~ s/^\s*//;
      $key =~ s/\s*$//;
      undef ($val);
    }
    $list{$key} = $val;
  }
  return \%list;
}

sub getConfigList {
  my($self, $key, $section) = @_;
  my(@map);
  
  (@map) = split /;/, $self->getConfig($key, $section);
  for (my $i = 0; $i < @map; $i++) {
    $map[$i] =~ s/^\s*//;
    $map[$i] =~ s/\s*$//;
  }
  return \@map;
}

sub getDBModel {
  my($self) = @_;

  my($key, $mod);
  foreach $key (keys %dbmodel) {
    if ((!defined($mod)) || ($key > $mod)) { $mod = $key; }
  }
  return $mod;
}

sub addConfig {
  my($self, $section, $attr) = @_;
  
  if (!exists($self->{sections}->{$section})) {
    $self->{sections}->{$section} = $attr;
  } else {
    print "ERROR --- can't add section $section to config - already exists\n";
  }
}

# ------------------------------------------------- private methods

sub _readConfig {
  # --- read section configuration file
  my($self, $file) = @_;
  my($currSect, %currCfg, $key, $val, $chr, $line);

  $currSect  = '';
  unless (open(INFILE, $file)) {
    print "WARNING --- Can't open config file $file\n";
    return 0;
  }
  while (<INFILE>) {
    chomp;
    $chr = chop;
    if (ord($chr) != 13) { $_ .= $chr; }           # in case we get a DOS file on UNIX
    s/#.*$//g;
    $line = $_;
    if ($_ =~ /:\s*\{/) {
      while ($line !~ /\}\s*$/) {
        $line .= <INFILE>;
        chomp($line);
        $chr = chop($line);
        if (ord($chr) != 13) { $line .= $chr; }    # in case we get a DOS file on UNIX
        $line =~ s/(?<!\\)#.*$//g;
      }
      $line =~ s/\\#/#/g;
      $line =~ s/:\s*\{/: /;
      $line =~ s/\}\s*$//;
    }
    if ($line && ($line !~ /^\s*$/)) {
      if ($line =~ /^\s*\[\s*(\S+)\s*\]\s*$/) {
        if ($currSect) { $self->_storeConfig($currSect, \%currCfg); }
        undef %currCfg;
        $currSect = $1;
      } else {
        $line =~ /^\s*([^:\s]+)\s*:\s*(.+)$/;
        $key  = $1;
        $val  = $2;
        $val  =~ s/\s+$//;
        $currCfg{$key} = $val;
      }
    }
  }
  $self->_storeConfig($currSect, \%currCfg);
  close INFILE;
  return 1;
}

sub _storeConfig {
  # --- check that all mandatory items were defined and store into $self->{sections}
  my($self, $section, $cfgPtr) = @_;
  my($key);
  
  if ($section eq 'GENERAL') {
    $self->{general} = { %$cfgPtr };
  } else {
    foreach $key (keys %mandatory) {
      if (!exists(${$cfgPtr}{$key})) {
        die "ERROR   --- Config of section $section does not contain value for mandatory item '$key'\n";
      }
    }
    ${$self->{sections}}{$section} = { %$cfgPtr };
  }
}

1;