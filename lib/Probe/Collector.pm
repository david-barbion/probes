package Probe::Collector;

use strict;
use warnings;

use Data::Dumper;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(unpack_archive read_meta_file register_result_set load_csv_file
		 update_counter);


our $dbh; # A connected handle to the DB
our $errstr;

sub reset_errstr {
    $errstr = "";
}

sub unpack_archive {
    my ($tarball, $dest) = @_;

    reset_errstr();

    # Find out the dirname inside the tarball, it is the basename of
    # the tarball
    my $basename;
    if ($tarball =~ m!(.*)/([^/]+)$!) {
	$basename = $2;
    } else {
	$basename = $tarball;
    }

    $basename =~ s!\.tgz$!!;

    # Unpack
    if (system("tar -xzf $tarball -C $dest")) {
	$errstr = "Unable to extract the archive";
	return undef;
    }

    return "$dest/$basename";
}

# remove probe list: use the source_path instead, and replace
sub read_meta_file {
    my $archive_dir = shift;

    reset_errstr();

    my $metafile = qq{$archive_dir/META};

    my $m;
    # Read the META file
    if (! -f "$metafile") {
	$errstr = "META file not found";
	return $m;
    }

    if (!open(META, "$metafile")) {
	$errstr = "Could not open META file: $!";
	return $m;
    }

    # Read the META file
    $m = { };
    while (my $line = <META>) {
	chomp $line;
	foreach my $k (qw/version description hostname chain/) {
	    $m->{$k} = $1 if $line =~ m!^$k: "(.+)"$!;
	}
    }
    close(META);

    # Find the list of files. Get the info from the DB and filter on the
    # contents of the archive because we get the target table
    # definition from the DB
    my $sth = $dbh->prepare(qq{SELECT id, target_ddl_query, source_path FROM probes WHERE enabled});
    unless ($sth->execute()) {
	$sth->finish;
	$dbh->rollback;
	$errstr = "Could not list list probes from the DB";
	return undef;
    }

    $m->{probes} = [ ];
    while (my ($i, $t, $p) = $sth->fetchrow()) {
	if (-f "${archive_dir}/${p}") {
	    push @{$m->{probes}}, { id => $i,
				    ddl => $t,
				    file => $p };
	}
    }
    $sth->finish;

    return $m;
}

sub register_result_set {
    my ($meta, $name, $desc, $uid) = @_;

    reset_errstr();

    $name = $meta->{hostname} if (!defined($name));
    $desc = $meta->{description} if (!defined($desc));

    # Check if the result set already exists
    my $sth = $dbh->prepare(qq{SELECT id, set_name, chain_id FROM results WHERE lower(set_name) = lower(?)});
    unless ($sth->execute($name)) {
	$sth->finish;
	$dbh->rollback;
	$errstr = "Could not check if results exists already exists";
	return undef;
    }
    my ($id_set, $set_name, $chain) = $sth->fetchrow();
    $sth->finish;

    if (defined $id_set) {
	if ($chain >= $meta->{chain}) {
	    # already loaded
	    $dbh->rollback;
	    $errstr = "Archive already loaded: $chain $meta->{chain}";
	    return undef;
	}

	# update the chain number
	$sth = $dbh->prepare(qq{UPDATE results SET chain_id = ? WHERE id = ?});
	unless ($sth->execute($meta->{chain}, $id_set)) {
	    $sth->finish;
	    $dbh->rollback;
	    $errstr = "Could not update the result set";
	    return undef;
	}
	$sth->finish;
    } else {
	# Register the result set when it does not exist
	$sth = $dbh->prepare(qq{INSERT INTO results (set_name, description, upload_time, chain_id, id_owner)
VALUES (?, ?, NOW(), ?, ?) RETURNING id});
	unless ($sth->execute($name, $desc, $meta->{chain}, $uid)) {
	    $sth->finish;
	    $dbh->rollback;
	    $errstr = "Could not register result set";
	    return undef;
	}
	($id_set) = $sth->fetchrow();
	$sth->finish;
    }

    my $schema = "data_${id_set}";

    # Check if the schema already exists
    $sth = $dbh->prepare(qq{SELECT nspname FROM pg_namespace WHERE nspname = ?});
    unless ($sth->execute($schema)) {
	$sth->finish;
	$dbh->rollback;
	$errstr = "Could not check if the schema exists";
	return undef;
    }
    my ($nsp) = $sth->fetchrow();
    $sth->finish;

    if (! defined $nsp) {
	unless ($dbh->do(qq{CREATE SCHEMA $schema})) {
	    $dbh->rollback;
	    $errstr = "Could not create the schema";
	    return undef;
	}
    }

    $meta->{schema} = $schema;
    $meta->{id_set} = $id_set;

    return $meta;
}

sub load_csv_file {
    my ($meta, $file) = @_;

    reset_errstr();

    my $schema = $meta->{schema};
    my $id_set = $meta->{id_set};

    my $p;
    # Search the file inside the probe list
    foreach my $mp (@{$meta->{probes}}) {
	my $re = $mp->{file} . "\$";
	if ($file =~ m/$re/) {
	    $p = $mp;
	    last;
	}
    }
    return undef unless defined $p;

    # Set the search path to the new schema to create the tables there
    unless($dbh->do(qq{SET search_path TO $schema})) {
	$dbh->rollback;
	$errstr = "Could not update the search path";
	return undef;
    }

    my $sth;

    # Create a savepoint to avoid failing everything
    $dbh->pg_savepoint('before_copy');

    # Create the table if needed
    my ($table) = $p->{ddl} =~ m!CREATE TABLE (\w+)\s*\(!i;
    if (defined $table) {
	$sth = $dbh->prepare(qq{SELECT tablename FROM pg_tables WHERE tablename = ? AND schemaname = ?});
	$sth->execute($table, $schema);
	my ($t) = $sth->fetchrow();
	if (! defined $t) {
	    unless ($dbh->do($p->{ddl})) {
		$dbh->pg_rollback_to('before_copy');
		$errstr = "Could not create target table";
		return undef;
	    }
	}
	$sth->finish;
    }

    # Load the data
    if (!open(CSV, $file)) {
	$dbh->pg_rollback_to('before_copy');
	return undef;
    }

    $dbh->do(qq{COPY $table FROM STDIN CSV NULL ''});
    while (my $line = <CSV>) {
	# Strip comments, and empty line
	next if ($line =~ m!^($|#)! || $line =~ m!LINUX-RESTART\n!);

	unless ($dbh->pg_putcopydata($line)) {
	    close(CSV);
	    $dbh->pg_rollback_to('before_copy');
	    $errstr = "Could not COPY line";
	    return undef;
	}
    }
    close(CSV);

    unless($dbh->pg_putcopyend()) {
	$dbh->pg_rollback_to('before_copy');
	$errstr = "Could not finish COPY operation";
	return undef;
    }

    # Link the probe to the result set
    $sth = $dbh->prepare(qq{SELECT id_result FROM public.probes_in_sets WHERE id_result = ? AND id_probe = ?});
    $sth->execute($id_set, $p->{id});
    my ($s) = $sth->fetchrow();
    $sth->finish;

    if (!defined $s) {
	$sth = $dbh->prepare(qq{INSERT INTO public.probes_in_sets (id_result, id_probe) VALUES (?, ?)});
	unless($sth->execute($id_set, $p->{id})) {
	    $dbh->pg_rollback_to('before_copy');
	    $errstr = "Could not register probe for the result set";
	    return undef;
	}
    }

    # Reset the search_path
    unless($dbh->do(qq{RESET search_path})) {
	$dbh->pg_rollback_to('before_copy');
	$errstr = "Could not reset the search path";
	return undef;
    }

    # Release the savepoint
    $dbh->pg_release('before_copy');

    return 1;
}

sub update_counter {
    my $user_id = shift;

    my $rc = 0;

    return $rc unless defined $user_id;

    my $sth = $dbh->prepare(qq{UPDATE users SET upload_count = upload_count + 1 WHERE id = ?});
    $rc = 1 if defined $sth->execute($user_id);
    $sth->finish;

    return $rc;
}


sub clean {
    my ($tarball, $dir) = @_;

    reset_errstr();

    system("rm -rf $tarball");
    system("rm -rf $dir");

}

1;
