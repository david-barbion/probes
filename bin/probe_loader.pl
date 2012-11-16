#!/usr/bin/perl

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

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
my $set_name;
my $owner;
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
  -n, --name=TEXT          overwrite the name of the result
  -o, --owner=USER         give ownership to this user

  -?, --help               print this help

};
    exit 1;
}

GetOptions("dbname|d=s" => \$dbname,
	   "username|U=s" => \$username,
	   "host|h=s" => \$host,
	   "port|p=i" => \$port,
	   "password|w=s" => \$password,
	   "workdir|D=s" => \$work_dir,
	   "name|n=s" => \$set_name,
	   "owner|o=s" => \$owner,
	   "help|?" => \$help) or die usage();
usage() if $help;


# Sanity check
my $archive = $ARGV[0];
if (! defined $archive) {
    print "Missing archive\n";
    exit 1;
}

# Prepare workdir
system("mkdir -p $work_dir");
if ($? >> 8) {
    print "Could not create $work_dir\n";
    exit 1;
}

# Unpack
my $archive_dir = unpack_archive($archive, $work_dir);
unless ($archive_dir = unpack_archive($archive, $work_dir)) {
    print "Unpack failed: ", $Probe::Collector::errstr, "\n";
    exit 1;
}

# Connect to the DB
my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",
 		       $username,
 		       $password,
 		       {AutoCommit => 0, RaiseError => 1, PrintError => 1});

$Probe::Collector::dbh = $dbh;

my $sth;


# Read the information from the meta file
my $meta_file = read_meta_file($archive_dir);


# When the target owner is specified, retrieve its uid from the
# DB. Fallback on the default uid (1 from admin)
if (defined $owner) {
    $sth = $dbh->prepare(qq{SELECT id FROM users WHERE username = ?});
    $sth->execute($owner);
    my ($id) = $sth->fetchrow;
    $sth->finish;

    if (defined $id) {
	$uid = $id;
    }
}

# Register the result. Data can be appended
unless ($meta_file = register_result_set($meta_file, $set_name, undef, $uid)) {
    print "Result set registration failed: ", $Probe::Collector::errstr, "\n";
    $dbh->rollback;
    $dbh->disconnect;
    exit 1;
}

# Load each file. A savepoint is used to safely discard files with
# errors, so db operations are still possible afterward
foreach my $f (<$archive_dir/*/*.csv>) {
    print "$f: ";
    unless (load_csv_file($meta_file, $f)) {
	print "failed:", $Probe::Collector::errstr,"\n";
	next;
    }
    print "done\n";
}

# Update the upload counter of the owner
unless (update_counter($uid)) {
    $dbh->rollback;
    $dbh->disconnect;
    print "Upload counter update failed";
    exit 1;
}

$dbh->commit;
$dbh->disconnect;
