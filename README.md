# dumpInfluxDB
Dump Influx 1.x database to Excel
## Introduction
This perl script dumps an InFlux 1.x database into an Excel file for further analysis, adds some calculated
columns and creates charts, all controlled from a config file. (Charts are considered an experimental
feature at this time).

A detailed description is in this .pdf file: [Dump_InFluxDB Users Guide](./Dump_InFluxDB%20Users%20Guide.pdf). Many of the examples have been made based on an Influx database created with the Photovoltaic monitoring system [Solaranzeige](https://solaranzeige.de/phpBB3/solaranzeige.php), but the dumper should be usable for any other Influx database.

Note: There is no intent to adapt the functionality described here to Influx 2.x in the foreseeable future.

## Version History
see users guide; current version is 1.01.00, 2021-08-08

## Disclaimer
The author cannot provide any warranty for fitness for any task, including those described in the Users Guide. It is possible that certain queries (specifically if covering a lot of data) can tax the Influx server and possibly create performance bottle-necks on other tasks running in parallel.

## Licence
Distributed under the terms of the GNU General Public Licence v3.