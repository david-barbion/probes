#!/usr/bin/perl

use strict;
use warnings;

# Update this line to be able to find the Probe::Collector module
use lib join '/', '/home/orgrim/dev/pg_probe/src', 'lib';

use DBI;
use Probe::Collector;
use Data::Dumper;
use Getopt::Long qw{ :config bundling no_ignore_case_always no_auto_abbrev};


my $dbname = "probe";
my $username = "probe";
my $password = "pg_probe";
my $host = "localhost"; # /tmp/ pour les sockets Unix
my $port = "5432";
my $work_dir = "/tmp/probe_load";
my $uid = 1;
my $help;

sub usage {
    print qq{usage: $0 [options] archive
options:
  -d, --dbname=DATABASE    connect to database ("$dbname")
  -h, --host=HOSTNAME      database server host or socket directory ("$host")
  -p, --port=PORT          database server port ("$port")
  -U, --username=USERNAME  database user name ("$username")
  -w, --password           user's password

  -D, --workdir=DIR        work directory where to extract files ("$work_dir")

  -?, --help               print this help

};
    exit 1;
}

GetOptions("dbname=s" => \$dbname,
	   "username|U=s" => \$username,
	   "host|h=s" => \$host,
	   "port|p=i" => \$port,
	   "password|w=s" => \$password,
	   "workdir|D=s" => \$work_dir,
	   "help|?" => \$help) or die usage();
usage() if $help;


my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",
 		       $username,
 		       $password,
 		       {AutoCommit => 0, RaiseError => 1, PrintError => 1});

$Probe::Collector::dbh = $dbh;

my $archive = $ARGV[0];
if (! defined $archive) {
    print "Missing archive\n";
    exit 1;
}

system("mkdir -p $work_dir");
if ($? >> 8) {
    print "Could not create $work_dir\n";
    exit 1;
}

my $archive_dir = unpack_archive($archive, $work_dir);
unless ($archive_dir = unpack_archive($archive, $work_dir)) {
    print "Unpack failed: ", $Probe::Collector::errstr, "\n";
    exit 1;
}

my $meta_file = read_meta_file($archive_dir);

unless ($meta_file = register_result_set($meta_file, undef, undef, $uid)) {
    print "Result set registration failed: ", $Probe::Collector::errstr, "\n";
    exit 1;
}

foreach my $f (<$archive_dir/*/*.csv>) {
    print "$f: ";
    unless (load_csv_file($meta_file, $f)) {
	print "failed:", $Probe::Collector::errstr,"\n";
	next;
    }
    print "done\n";
}

$dbh->commit;
