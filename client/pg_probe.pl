#!/usr/bin/perl

use strict;
use warnings;

use DBI;


# input:
# we will need psql
# a target db to load stuff
# connections parameters to retrieve stuff

# prepare the psql script file that will run the queries

# run the queries in a loop. We will daemonize with a pid file
# somewhere and use signals to stop, restart, rotate the csv and so on

# once the data retrieved, we need to easily pack that in a tarball
# that could be uploaded somewhere to be loaded in a db

# before loading we need a db with a schema to separate probes run, so
# we create it along with the tables depending on the queries run

# then we can load

use Getopt::Long;

my $dbname = "probe"; # DBROI
my $username = "probe"; # postgres
my $password = "";
my $host = "localhost"; # /tmp/ pour les sockets Unix
my $port = "5432"; # 5432
my $help;
my $title;
my $desc;

sub usage {
    print qq{usage: $0 [options] directory
options:
  -d, --dbname=DATABASE    connect to database ("$dbname")
  -h, --host=HOSTNAME      database server host or socket directory ("$host")
  -p, --port=PORT          database server port ("$port")
  -U, --username=USERNAME  database user name ("$username")
  -w, --password           user's password

  -t, --title              target schema
  -m, --message            description

  -?, --help               print this help

};
    exit 1;
}

GetOptions("dbname=s" => \$dbname,
	   "username|U=s" => \$username,
	   "host|h=s" => \$host,
	   "port|p=i" => \$port,
	   "password|w=s" => \$password,
	   "title=s" => \$title,
	   "message=s" => \$desc,
	   "help|?" => \$help) or die usage();
usage() if $help;

unless (defined($ARGV[0])) {
    print qq{data directory is missing.\n};
    usage();
}

my $data = $ARGV[0];

if (! -d $data) {
    print "bad input directory\n";
    exit 1;
}

if (!defined($title) || !defined($desc)) {
    print "title and desc are mandatory\n";
    exit 1;
}

my $schema = $title;
$schema =~ s/\s/_/g;
$schema =~ s/\W//g;

my $dbh = DBI->connect("dbi:Pg:dbname=$dbname;host=$host;port=$port",
  		       $username,
  		       $password,
  		       {AutoCommit => 0, RaiseError => 1, PrintError => 1});

# add the definition of the upload and create the schema with its tables
my $sth = $dbh->prepare(qq{INSERT INTO probe_sets (set_name, nsp_name, description, upload_time) VALUES (?, lower(?), ?, NOW()) RETURNING id});
$sth->execute($title, $schema, $desc);

my $set_id = $sth->fetchrow_arrayref()->[0];

$sth->finish;

$dbh->do("CREATE SCHEMA $schema");

my $stats = { "bgwriter_stats" => "CREATE TABLE #NSP#.bgwriter_stats (
  datetime timestamptz,
  checkpoints_timed bigint,
  checkpoints_req bigint,
  buffers_checkpoint bigint,
  buffers_clean bigint,
  maxwritten_clean bigint,
  buffers_backend bigint,
  buffers_backend_fsync bigint,
  buffers_alloc bigint,
  stats_reset timestamptz
)",
	      cluster_hitratio => "CREATE TABLE #NSP#.cluster_hitratio (
  datetime timestamptz,
  cache_hit_ratio float
)",
	      connections => "CREATE TABLE #NSP#.connections (
  datetime timestamptz,
  total int,
  active int,
  waiting int,
  idle_in_xact int
)",
	      databases_hitratio => "CREATE TABLE #NSP#.databases_hitratio (
  datetime timestamptz,
  database text,
  cache_hit_ratio float
)",
	      database_stats => "CREATE TABLE #NSP#.database_stats (
  datetime timestamptz,
  datid bigint,
  datname text,
  numbackends  bigint,
  xact_commit bigint,
  xact_rollback bigint,
  blks_read bigint,
  blks_hit bigint,
  tup_returned bigint,
  tup_fetched bigint,
  tup_inserted bigint,
  tup_updated bigint,
  tup_deleted bigint,
  conflicts bigint,
  stats_reset timestamptz
)",
	      io_user_indexes => "CREATE TABLE #NSP#.io_user_indexes (
  datetime timestamptz,
  relid bigint,
  indexrelid bigint,
  schemaname text,
  relname text,
  indexrelname text,
  idx_blks_read bigint,
  idx_blks_hit bigint
)",
	      io_user_tables => "CREATE TABLE #NSP#.io_user_tables (
  datetime timestamptz,
  relid bigint,
  schemaname text,
  relname text,
  heap_blks_read bigint,
  heap_blks_hit bigint,
  idx_blks_read bigint,
  idx_blks_hit bigint,
  toast_blks_read bigint,
  toast_blks_hit bigint,
  tidx_blks_read bigint,
  tidx_blks_hit bigint
)",
# 	      locks => "CREATE TABLE #NSP#.locks (
#   datetime timestamptz,
#   locktype bigint,
#   database bigint,
#   relation bigint,
#   page bigint,
#   tuple bigint,
#   virtualxid text,
#   transactionid bigint,
#   classid bigint,
#   objid bigint,
#   objsubid bigint,
#   virtualtransaction text,
#   pid bigint,
#   mode text,
#   granted boolean,
#   datid bigint,
#   datname text,
#   procpid bigint,
#   usesysid bigint,
#   usename text,
#   application_name text,
#   client_addr text,
#   client_hostname text,
#   client_port text,
#   backend_start timestamptz,
#   xact_start timestamptz,
#   query_start timestamptz,
#   waiting boolean,
#   current_query text
# )",
	      read_write_ratio => "CREATE TABLE #NSP#.read_write_ratio (
  datetime timestamptz,
  relation text,
  seq_tup_read bigint,
  idx_tup_fetch bigint,
  n_tup_read bigint,
  n_tup_ins bigint,
  n_tup_upd bigint,
  n_tup_del bigint,
  ratio float
)",
# 	      stat_activity => "CREATE TABLE #NSP#.stat_activity (
#   datetime timestamptz,
#   datid bigint,
#   datname text,
#   procpid bigint,
#   usesysid bigint,
#   usename text,
#   application_name text,
#   client_addr text,
#   client_hostname text,
#   client_port text,
#   backend_start timestamptz,
#   xact_start timestamptz,
#   query_start timestamptz,
#   waiting boolean,
#   current_query text
# )",
	      tables_hitratio => "CREATE TABLE #NSP#.tables_hitratio (
  datetime timestamptz,
  schema text,
  relation text,
  table_ratio float,
  index_ratio float,
  ratio float
)",
	      user_indexes => "CREATE TABLE #NSP#.user_indexes (
  datetime timestamptz,
  relid bigint,
  indexrelid bigint,
  schemaname text,
  relname text,
  indexrelname text,
  idx_scan bigint,
  idx_tup_read bigint,
  idx_tup_fetch bigint
)",
	      user_tables => "CREATE TABLE #NSP#.user_tables (
  datetime timestamptz,
  relid bigint,
  schemaname text,
  relname text,
  seq_scan bigint,
  seq_tup_read bigint,
  idx_scan bigint,
  idx_tup_fetch bigint,
  n_tup_ins bigint,
  n_tup_upd bigint,
  n_tup_del bigint,
  n_tup_hot_upd bigint,
  n_live_tup bigint,
  n_dead_tup bigint,
  last_vacuum timestamptz,
  last_autovacuum timestamptz,
  last_analyze timestamptz,
  last_autoanalyze timestamptz,
  vacuum_count bigint,
  autovacuum_count bigint,
  analyze_count bigint,
  autoanalyze_count bigint
)" };

my $probes_h = $dbh->prepare("INSERT INTO probes_in_sets (id_set, id_probe) VALUES (?, (SELECT id FROM probes WHERE probe_name = ?));");
foreach my $t (keys %{$stats}) {

    if (-f "${data}/${t}.csv") {

	# Create the target table in the proper schema
	my $qct = $stats->{$t};
	$qct =~ s/#NSP#/$schema/e;
	$dbh->do($qct);

	# Load the data in the target table
	open(CSV, "${data}/${t}.csv");
	$dbh->do("COPY $schema.${t} FROM STDIN WITH DELIMITER ';' NULL ''");
	while (<CSV>) {
	    next if m/^datetime/;
	    $dbh->pg_putcopydata($_);
	}
	close(CSV);
	$dbh->pg_putcopyend();

	# Add the table name to the list of available tables for the probe
	$probes_h->execute($set_id, $t);

    }
}

$dbh->commit;
$dbh->disconnect;
