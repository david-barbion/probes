#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use Getopt::Long;
use Mojo::JSON;
use Sys::Syslog qw( :DEFAULT setlogsock);
use DBI;
use IO::Handle;

use Data::Dumper;

# Configuration
my $logfile = "collector.log";
my $syslog = 0;
my $watchdir;
my $interval = 30;

# Globals
my $foreground = 0;
my $dbh;
my $config_file;
my $help;
my $config = { };
my $running = 1;

sub logger {
    # Log to syslog or stderr (which can be redirected to a log file
    if ($syslog) {
	openlog('probe_collector','','user');
	map { syslog('info', $_) } @_ if scalar(@_);
	closelog();
    } else {
	my $now = localtime;
	map { print STDERR qq{[$now] $_\n} } @_ if scalar(@_);
    }
}

sub daemonize {
    # fork and go to background, detach from tty
    my $child = fork();
    exit 0 if $child;

    close(STDOUT);
    close(STDERR);
    open STDOUT,">/dev/null";
    open STDERR,">>$logfile";
    autoflush STDERR 1;
    close(STDIN);
    POSIX::setsid();
    chdir '/';
}

sub sighup {
    # block sighup
    local $SIG{HUP} = "IGNORE";

    # reopen logfile
    if (! $syslog) {
	logger `pwd`;
	logger qq{Reopening logfile: $logfile};

#	close STDERR;
#	open STDERR,">>$logfile";
    }

    # Reload the configuration
    $config = load_config($config_file);
}

sub sigterm {
    my $signame = shift;

    # block the incoming signal
    local $SIG{$signame} = "IGNORE";

    logger qq{Exiting};
    $running = 0;
}

sub database {
    my $config = shift;

    # data source name
    my $dsn = $config->{dsn};

    # Check if we have a split dsn with fallback on defaults
    unless ($dsn) {
	my $database  = $config->{database} || "probe";
	my $dsn = "dbi:Pg:database=" . $database;
	$dsn .= ';host=' . $config->{host} if $config->{host};
	$dsn .= ';port=' . $config->{port} if $config->{port};
    }

    # Return a new database handle
    return DBI->connect($dsn, $config->{username},
		     $config->{password},
		     $config->{options} || { }
		    );
}

sub load_config {
    my $file = shift;

    open(CONF, $file) or die "Cannot open configuration file: $!\n";
    my $conf =  Mojo::JSON->decode(join('', <CONF>));
    close(CONF);

    $logfile = $conf->{collector}->{logfile};
    $syslog = $conf->{collector}->{syslog};
    $watchdir = $conf->{collector}->{watchdir};
    $interval = $conf->{colletor}->{naptime} ||= 30;

    return $conf;
}

sub main_loop {

    logger qq{Now watching: $watchdir};

    my %watchlist = ();
    # Watch the directory in an infinite loop
    while ($running) {
	my @todo = ();
	if (-d $watchdir) {
	    while (my $f = <$watchdir/*.tgz>) {
		next unless (-f $f);
		my $size = (stat($f))[7];
		# Remember the size of the file to check if it has been fully copied
		if (exists $watchlist{$f}) {
		    if ($size != $watchlist{$f}) {
			$watchlist{$f} = $size;
		    } else {
			my ($file) = $f =~ m!/([^/]+)$!;
			logger qq{Found $file};
			push @todo, $f;
			delete $watchlist{$f};
		    }
		} else {
		    $watchlist{$f} = $size;
		}
	    }
	    # Load that into the db
	    load_archives(@todo) if scalar @todo;
	}
	sleep($interval);
    }
}

sub unpack_archive {
    my ($tarball, $dest) = @_;

    # Move the tarball to the workdir
    if (system("mv $tarball $dest")) {
	logger qq{Could not move $tarball to $dest};
	next;
    }

    # Find out the dirname inside the tarball, it is the basename of
    # the tarball
    my $basename;
    if ($tarball =~ m!(.*)/([^/]+)$!) {
	$basename = $2;
    } else {
	$basename = $tarball;
    }

    # Update the path to the tarball after the move
    $tarball = "$dest/$basename";

    $basename =~ s!\.tgz$!!;

    # Unpack
    chdir($dest);
    if (system("tar xzf $tarball")) {
	logger qq{Unable to extract $tarball};
	return undef;
    }

    return $basename;
}

sub read_meta_file {
    my $metafile = shift;

    my $m;
    # Read the META file
    if (! -f "$metafile") {
	logger qq{META file does not exist};
	return $m;
    }

    if (!open(META, "$metafile")) {
	logger qq{Could not open META file: $!};
	return $m;
    }

    $m = { };
    while (my $line = <META>) {
	chomp $line;
	foreach my $k (qw/version name description chain sysstat/) {
	    $m->{$k} = $1 if $line =~ m!^$k: "(.+)"$!;
	}
	if ($line =~ m!^probe: (\d+) "(.+)"$!) {
	    $m->{probes} = [ ] unless exists $m->{probes};
	    push @{$m->{probes}}, $1;
	}
    }
    close(META);

    return $m;
}

sub load_csv_files {
    my $type = shift;
    my $table = shift;
    my @files = @_;

    my $e = 0;
    # Load everything using copy statements
  FILE: foreach my $file (@files) {
	if (!open(CSV, $file)) {
	    logger qq{Could not open $file: $!};
	    next;
	}

	# Create a savepoint in case the copy fails, so that we can
	$dbh->pg_savepoint('before_copy');
	$dbh->do(qq{COPY $table FROM STDIN CSV NULL ''});

	while (my $line = <CSV>) {
	    # Strip comments, and empty line
	    next if ($line =~ m!^($|#)! || $line =~ m!LINUX-RESTART\n!);

	    unless ($dbh->pg_putcopydata($line)) {
		$e++;
		logger qq{COPY $table failed in $file on: $line};
		close(CSV);
		$dbh->pg_rollback_to('before_copy');
		next FILE;
	    }
	}
	close(CSV);

	unless ($dbh->pg_putcopyend()) {
	    $e++;
	    logger qq{COPY $table failed in $file};
	    $dbh->pg_rollback_to('before_copy');
	    next FILE;
	}

	# Remove savepoint when no errors occur on the file
	$dbh->pg_release('before_copy');
    }

    # Return the number of errors
    return $e;
}

sub register_probe_in_set {
    my ($set, $probe) = @_;

    my $rb = 0;
    # Check if the probe is already registered
    my $sth =  $dbh->prepare(qq{SELECT id_set, id_probe FROM public.probes_in_sets WHERE id_set = ? AND id_probe = ?});
    $sth->execute($set, $probe);
    my ($s, $p) = $sth->fetchrow();
    $sth->finish;

    if (! defined $s) {
	$sth = $dbh->prepare(qq{INSERT INTO public.probes_in_sets (id_set, id_probe) VALUES (?, ?)});
	$rb = 1 unless $sth->execute($set, $probe);
    }
    $sth->finish;

    return $rb;
}

sub load_archives {
    my @archives = @_;

    # Prepare the workdir if it is missing
    my $workdir = "$watchdir/work";
    if (! -d $workdir) {
	if (system("mkdir -p $workdir")) {
	    logger qq{Could not create the work directory: $workdir};
	    return undef;
	}
    }

    $dbh = database($config->{database});

  ARCHIVE: foreach my $archive (@archives) {
	logger qq{Processing $archive};

	my $basename = unpack_archive($archive, $workdir) or next;
	my $meta = read_meta_file("$workdir/$basename/META") or next;

	# Check if a result set exists, matching the name of the target schema
	my $schema = $meta->{name};
	$schema =~ s!\s!_!g;
	$schema =~ s!\W!!g;

	my $sth = $dbh->prepare(qq{SELECT id, set_name FROM probe_sets WHERE nsp_name = ?});
	$sth->execute($schema);
	my ($set, $dbset) = $sth->fetchrow();
	$sth->finish;

	if (defined $dbset) {
	    logger qq{A result set already exists for $basename, data will be appended};
	} else {
	    # Register the result set when it does not exist
	    $sth = $dbh->prepare(qq{INSERT INTO probe_sets (set_name, nsp_name, description, upload_time)
VALUES (?, lower(?), ?, NOW())
RETURNING id});
	    $sth->execute($meta->{name}, $schema, $meta->{description});
	    ($set) = $sth->fetchrow();
	}

	# Check if the schema already exists
	$sth = $dbh->prepare(qq{SELECT nspname FROM pg_namespace WHERE nspname = ?});
	$sth->execute($schema);
	my ($nsp) = $sth->fetchrow();
	$sth->finish;

	if (! defined $nsp) {
	    unless ($dbh->do(qq{CREATE SCHEMA $schema})) {
		logger qq{Unable to create the target schema};
		$dbh->rollback;
		next;
	    }
	}

	# Get the probe information from the db
	my $probes = [ ];
	$sth = $dbh->prepare(qq{SELECT p.preload_command, p.target_ddl_query, p.source_path, t.runner_key
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
WHERE p.id = ?});
	foreach my $i (@{$meta->{probes}}) {
	    $sth->execute($i);
	    my ($p, $d, $s, $k) = $sth->fetchrow();
	    push @{$probes}, { id => $i, preload => $p, ddl => $d, path => $s, type => $k };
	}
	$sth->finish;

	# Set the search path to the new schema to create the table there
	$dbh->do(qq{SET search_path TO $schema});

	# Create all the needed tables and load the data
	$sth = $dbh->prepare(qq{SELECT tablename FROM pg_tables WHERE tablename = ? AND schemaname = ?});
	foreach my $p (@{$probes}) {
	    my ($table) = $p->{ddl} =~ m!CREATE TABLE (\w+)\s*\(!i;
	    if (defined $table) {
		$sth->execute($table, $schema);
		my ($t) = $sth->fetchrow();
		if (! defined $t) {
		    map { $dbh->do($_) } split /;/, $p->{ddl};
		    # XXX error handling
		}
	    }

	    # Prepare the CSV file
	    my @csv = ();
	    my $sp = $p->{path};
	    if (defined $p->{preload} and $p->{preload}) {
		my $path = $ENV{PATH};

		if ($p->{type} eq 'sar') {
		    # If it is a sysstat probe, check the version of the
		    # sa files and update the PATH accordingly: we need a
		    # config parameter to give the path where different
		    # versions of sysstat are installed along with a
		    # standard layout for versions
		    my $sysstat_home = sprintf("%s/%d/bin", $config->{collector}->{sysstat_home},
					       $meta->{sysstat});
		    $ENV{PATH} = $sysstat_home . ':' . $ENV{PATH};
		}

		# Use the C locale to ensure we end up with real CSV, not semicolons
		$ENV{LC_ALL} = 'C';

		# Run the command for each input file
		my $output = sprintf("%s/%d.csv", "$workdir/$basename", $p->{id});
		if ($sp =~ m!/$!) {
		    while (my $f = <$workdir/$basename/$sp*>) {
			next if (! -f $f || ($p->{type} eq 'sar' && $f !~ m!/sa\d+$!));
			my $cmd = $p->{preload};
			$cmd =~ s!\%f!$f!g;

			my $rc = system($cmd . " >> " . $output);
			if ($rc) {
			    logger qq{Could not run preload command on $f for $p->{id}};
			    $ENV{PATH} = $path;
			    next;
			}
		    }
		} else {
		    my $cmd = $p->{preload};
		    $cmd =~ s!\%f!$sp!;

		    my $rc = system($cmd . " >> " . $output);
		    if ($rc) {
			logger qq{Could not run preload command on $sp for $p->{id}};
			$ENV{PATH} = $path;
			next;
		    }
		}
		$ENV{PATH} = $path;

		push @csv, $output;
	    } else {
		if ($sp =~ m!/$!) {
		    while (my $f = <$workdir/$basename/$sp*>) {
			next if (! -f $f);
			push @csv, $f;
		    }
		} else {
		    push @csv, "$workdir/$basename/$sp";
		}

	    }

	    # Load the data of the probe
	    load_csv_files($p->{type}, $table, @csv);

	    # Ensure the probe is linked to the result set
	    if (register_probe_in_set($set, $p->{id})) {
		$sth->finish;
		$dbh->rollback;
		logger qq{Could not link probe $p->{id} to set $set};

		# The unpacked dir and tarball will stay in the workdir
		next ARCHIVE;
	    }
	} # end each probe
	$sth->finish;

	# Reset the search_path before processing the next archive
	$dbh->do(qq{RESET search_path});

	# Each archive is loaded in a single transaction
	$dbh->commit;

	logger qq{Loaded $basename};

	# Remove processed archive
	system("rm -rf $workdir/$basename");
	system("rm -f $workdir/$basename.tgz");
    }

    $dbh->disconnect;
    $dbh = undef;
}

sub usage {
    print qq{usage: $0 [options]
options:
  -c, --config=FILE        path to the configuration file
  -l, --logfile=FILE       path to the logfile
  -F, --foreground         do not detach from console
  -h, --help               print usage

};
    exit 1
}

GetOptions("config=s" => \$config_file,
	   "logfile=s" => \$logfile,
	   "foreground|F" => \$foreground,
	   "help" => \$help) or die usage();
usage if ($help);

unless (defined $config_file) {
    logger qq{Unable to find configuration file};
    usage;
}

# Load the configuration file
my $cwd = `pwd`; chomp $cwd;
$config_file = "$cwd/$config_file";
$config = load_config($config_file);

# Setup the signal handlers
$SIG{HUP} = \&sighup;
$SIG{INT} = $SIG{TERM} = \&sigterm;

# Fork to background if ask
daemonize() unless $foreground;

logger qq{probe_collector started, entering watch loop};

# Watch the directory and load archives into the database
main_loop();
