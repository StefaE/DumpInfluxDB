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

package Dump_InFluxDB::Dump;
use strict;

sub new {
  my($self, $cfg, $args, $where) = @_;
  
  $self = bless{ cfg       => $cfg,                                             # config object
                 args      => $args,                                            # pointer to %args command line arguments
                 influx    => $cfg->getConfig("influx") || "influx",
                 xlsx      => '',
                 wbook     => '',
                 wsheets   => {},
                 where     => $where,
                 outTables => {},
                 fieldIdx  => {}
               }, $self;
  
  return $self;
}

sub getTables {
  my($self) = @_;
  my($outList, $tabList, @inList, $tableData);
  
  $outList = $self->{cfg}->getConfigMap("tables");
  if (!scalar keys %$outList) { $outList = { "01_Data" => "PV, AC, Batterie, Summen" }; }
  $tabList = $self->{args}->{T};
  if (!$tabList) {
    $tabList = join(',', keys %{$outList});
  }
  $tabList = ",$tabList,";
  foreach my $table (sort keys %$outList) {
    unless ($tabList =~ /,$table,/) { next; }
    print "  -- getting data for tab $table\n";
    $self->{outTables}->{$table} = [ [], {} ];
    @inList = split(/\s*\|\s*/, $outList->{$table});
    for (my $i = 0; $i < @inList; $i++) {
      $tableData = $self->getTable($inList[$i], $table);
      if (!$i) { $self->{outTables}->{$table} = $tableData; }
      else {
        push @{$self->{outTables}->{$table}->[0]}, @{$tableData->[0]};
        foreach my $time (sort keys %{$self->{outTables}->{$table}->[1]}) {
          if (exists($tableData->[1]->{$time}) && scalar(@{$self->{outTables}->{$table}->[1]->{$time}}) > 0) {
            push @{$self->{outTables}->{$table}->[1]->{$time}}, @{$tableData->[1]->{$time}};
          } else {
            print "     WARNING --- Time inconsistencies at $time in table $table found\n";
            if (!exists($tableData->[1]->{$time})) {
              push @{$self->{outTables}->{$table}->[1]->{$time}}, ('NA') x scalar(@{$tableData->[0]});
            }
          }
        }
      }
    }
  }
}

sub getTable {
  my($self, $table, $outTable) = @_;
  my($sql, $cmd, $fh, $isHeader, @fields, @header, %table, $host, $db, $isSelect);
  
  $host = $self->{cfg}->getConfig("host", $outTable) || "localhost";
  $db   = $self->{cfg}->getConfig("db", $outTable)   || "solaranzeige";

  if ($table =~ /^select/i) {
    $sql      = $table;
    $sql      =~ s/\$timeFilter/$self->{where}/g;
    $table    = "-- <SELECT> statement";
    $isSelect = 1
  } else {
    $sql      = "select * from $table where $self->{where}";
    $isSelect = 0
  }
  $cmd = "$self->{influx} -host $host -database $db -execute \"$sql\" -format csv";
  if ($self->{args}->{v}) { printf("     Cmd: -- %s\n", $cmd); }

  print "     -- getting data for Influx table $table\n";
  open $fh, "-|", $cmd;
  $isHeader = 1;
  while (my $rec = <$fh>) {
    chomp $rec;
    @fields = split(/,/, $rec);
    if ($isHeader) {
      for (my $i = 2; $i < @fields; $i++) {
        if ($isSelect) { $header[$i-2] = $fields[$i];          }
        else           { $header[$i-2] = "$table.$fields[$i]"; }
      }
      $isHeader = 0;
    } else {
      $table{$fields[1]} = [ @fields[ 2 .. scalar(@fields) - 1 ] ];
    }
  }
  return [ \@header, \%table ];
}

sub openXLSX {
  my($self, $from) = @_;
  my($file);
  
  $file  = $self->{cfg}->getConfig('xlsx') || "SolarAnzeige";
  $file  = $self->{args}->{O} || $file;
  $file .= "_" . $from->year() . "-" . sprintf("%02d", $from->month()) . "-" . sprintf("%02d", $from->day()) . ".xlsx";
  unless ($self->{args}->{o}) {
    if (-e $file) {
      die "ERROR --- Output file $self->{xlsx} already exists. Use -o to overwrite\n";
    }
  }
  $self->{xlsx} = $file;
  $self->{wbook} = Excel::Writer::XLSX->new($self->{xlsx}) || die "ERROR --- Can't open output file $self->{xlsx} (open in Excel?); aborted\n";
}

sub writeXLSX {
  my($self) = @_;
  my($wsheet, $outList, $tz, $t, $fmtHead, $fmtColHead, $fmtEpoch, $fmtDateTime,
     $dropFields, $formulas, $rows, $cols, $dCols);
  
  print "  -- writing output file $self->{xlsx}\n";

  $tz         = $self->{cfg}->getConfig('time_zone') || 'UTC';
  print "     -- time zone of output file: $tz\n";
  $fmtHead    = $self->{wbook}->add_format( bold => 1, bg_color => '#C5D9F1', bottom => 1 );
  $fmtColHead = $self->{wbook}->add_format( bold => 1, bg_color => '#C5D9F1', bottom => 1, align => 'left', rotation => 90 );
  $fmtEpoch   = $self->{wbook}->add_format();
  $fmtEpoch->set_num_format('#');
  $fmtDateTime = $self->{wbook}->add_format(num_format => "yyyy-mm-dd hh:mm");
  
  foreach my $table (sort keys %{$self->{outTables}}) {
    print "     -- writing tab $table\n";
    if (!scalar keys %{$self->{outTables}->{$table}->[1]}) {
      print "        WARNING --- No data found for selected time period for tab $table, skipped\n";
      next;
    }
    $wsheet     = $self->{wbook}->add_worksheet($table);
    $wsheet->write_row(0, 0, ["Epoch", "DateTime"], $fmtHead);
    $dropFields = $self->{cfg}->getConfigList('drop', $table);
    
    my %rawIdx;
    for (my $i = 0; $i < scalar @{$self->{outTables}->{$table}->[0]}; $i++) {
      $rawIdx{ $self->{outTables}->{$table}->[0]->[$i] } = $i;                  # original index of each field
    }
    for (my $i = 0; $i < scalar @$dropFields; $i++) {
      my $found = 0;
      for (my $j = 0; $j < scalar @{$self->{outTables}->{$table}->[0]}; $j++) {
        if ($self->{outTables}->{$table}->[0]->[$j] eq $dropFields->[$i]) {
          splice @{$self->{outTables}->{$table}->[0]}, $j, 1;                   # remove dropped field from header fields
          delete $rawIdx{ $dropFields->[$i] };                                  # remove from index list of fields to be dumped
          $found = 1;
          last;
        }
      }
      unless ($found) { print "        WARNING --- $dropFields->[$i] not found in table $table; not dropped\n"; }
    }
    my @idx;
    foreach my $key (keys %rawIdx) {
      push @idx, $rawIdx{$key};                                                 # list of index values to be dumped (needed for time series)
    }
    @idx = sort { $a <=> $b } @idx;                                             # ... sorted in the right order now
    $cols  = scalar @{$self->{outTables}->{$table}->[0]};
    $dCols = $cols;

    $self->{fieldIdx}->{$table} = {};
    use Excel::Writer::XLSX::Utility ':rowcol';
    for (my $i = 0; $i < $cols; $i++) {
      my $rc = xl_rowcol_to_cell(1, $i + 2);                                    # RowCol of column $i
      $rc =~ s/[0-9]//g;                                                        # strip off row information
      $self->{fieldIdx}->{$table}->{ $self->{outTables}->{$table}->[0]->[$i] } = $rc;
                                                                                # store Excel col. name (A ... XFD) for each column
    }

    $formulas = $self->{cfg}->getConfigMap('calculate', $table);
    foreach my $key (sort keys %$formulas) {
      push @{$self->{outTables}->{$table}->[0]}, $key;                          # header column for calculated column
      my $rc = xl_rowcol_to_cell(1, $cols + 2);                                 # RowCol of newly added calculated column
      $rc =~ s/[0-9]//g;                                                        # strip off row information
      $self->{fieldIdx}->{$table}->{$key} = $rc;                                # store Excel col. name (A ... XFD) for each column
      $cols++;
    }
    $self->{fieldIdx}->{$table}->{Epoch}    = 'A';
    $self->{fieldIdx}->{$table}->{DateTime} = 'B';
    foreach my $key (sort keys %$formulas) {
      for (my $i = 0; $i < $cols; $i++) {
        my $field  = $self->{outTables}->{$table}->[0]->[$i];
        my $rc     = $self->{fieldIdx}->{$table}->{$field};
        $formulas->{$key} =~ s/'$field'/$rc<_row_>/g;                           # convert field names in formula to Excel column
      }
      unless ($formulas->{$key} =~ /^=/) { $formulas->{$key} = "=" . $formulas->{$key}; }
      my @warn = ($formulas->{$key} =~ m/('[a-zA-Z0-9_\.]+')/g);
      for (my $i = 0; $i < scalar @warn; $i++) {
        print "        WARNING --- unresolvable column reference $1 in formula $table.$key\n";
      }
    }

    $wsheet->write_row(0, 2, $self->{outTables}->{$table}->[0], $fmtColHead);

    $rows = 0;
    foreach my $time (sort keys %{$self->{outTables}->{$table}->[1]}) {
      $rows++;
      if ($time !~ /^\d+$/) {
        print ("$time\n");
      }
      $t = DateTime->from_epoch(epoch => $time/1e9, time_zone => $tz);
      $wsheet->write($rows, 0, $time, $fmtEpoch);
      $wsheet->write_date_time($rows, 1, $t, $fmtDateTime);
      $wsheet->write_row($rows, 2, [ @{$self->{outTables}->{$table}->[1]->{$time}}[@idx] ]);
      my $c = 0;
      foreach my $key (sort keys %$formulas) {
        my $r = $rows+1;
        my $rowFormula = $formulas->{$key};
        $rowFormula    =~ s/<_row_>/$r/g;
        $wsheet->write($rows, $dCols + $c + 2, $rowFormula);
        $c++;
      }
    }
    $wsheet->set_column(0, 1, 20);
    $wsheet->autofilter(0, 0, $rows, $cols + 1);
    $wsheet->freeze_panes(1, 0);
    $self->{wsheets}->{$table} = $wsheet;
    
    $self->addCharts($table, $rows);
  }
  $self->{wbook}->close();
}

sub addCharts {
  my($self, $table, $rows) = @_;
  my($charts, @cmds, $code);
  
  $charts = $self->{cfg}->getConfigMap('charts', $table);
  foreach my $key (sort keys %$charts) {
    $code = '';                                                                 # will contain code for chart specified by $key
    $charts->{$key} =~ s/\s+/ /g;                                               # make code a bit more readable ...
    print "        -- constructing chart $key\n";
    
    @cmds = ($charts->{$key} =~ m/[a-z_2]+\s*\(.+?\)(?=\s*[a-z]|$)/g);
    for (my $i = 0; $i < scalar @cmds; $i++) {
      if ($cmds[$i] =~ /^add_series\s*\(.*(categories|values)\s*=>\s*('[a-zA-Z0-9_\.]+')\s*(,|\))/) {
        foreach my $field (keys %{$self->{fieldIdx}->{$table}}) {
          my $col         = $self->{fieldIdx}->{$table}->{$field};
          my $r           = $rows + 1;
          my $excelData   = "'=$table!$col" . "2:$col$r'";
          $cmds[$i]       =~ s/(categories|values)\s*=>\s*('$field')/$1 => $excelData/mg;
        }
        if ($cmds[$i] =~ /^add_series\s*\(.*(categories|values)\s*=>\s*('[a-zA-Z0-9_\.]+')\s*(,|\))/) {
          print "               WARNING --- unresolvable column reference $2 in chart $table.$key\n";
        }
      }
      if ($cmds[$i] =~ /^add_chart/) {
        $cmds[$i] = 'my $chart = $self->{wbook}->' . $cmds[$i] . ";\n";
      } elsif ($cmds[$i] =~ /^insert_chart/) {
        $cmds[$i] = '$self->{wsheets}->{$table}->' . $cmds[$i] . ";\n";
      } else {
        $cmds[$i] = '$chart->' . $cmds[$i] . ";\n";
      }
      $code .= $cmds[$i];
      if ($self->{args}->{v}) { printf("           %2d: %s", $i+1, $cmds[$i]); }
    }
    eval ( $code ) or do {
      print "               ERROR --- $@ in code for chart $table.$key\n";
    };
  }
}

1;