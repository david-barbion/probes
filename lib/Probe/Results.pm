package Probe::Results;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Probe::Collector;

sub list {
    my $self = shift;

    # # Require admin privileges
    # if (! $self->perm->is_admin) {
    # 	return $self->render('unauthorized', status => 401);
    # }

    my $dbh = $self->database;

    # Handle purge
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	if (exists $form_data->{purge}) {
	    my $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets WHERE id_result = ?});
	    foreach my $id (@{$form_data->{selection}}) {
		unless ($sth->execute($id)) {
		    $sth->finish;
		    $dbh->rollback;
		    $dbh->disconnect;
		    $self->msg->error("Could not delete links to probes");
		    return $self->redirect_to('results_list');
		}
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM report_contents WHERE id_result = ?});
	    foreach my $id (@{$form_data->{selection}}) {
		unless ($sth->execute($id)) {
		    $sth->finish;
		    $dbh->rollback;
		    $dbh->disconnect;
		    $self->msg->error("Could not delete links to reports");
		    return $self->redirect_to('results_list');
		}
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM results WHERE id = ?});
	    foreach my $id (@{$form_data->{selection}}) {
		unless ($sth->execute($id)) {
		    $sth->finish;
		    $dbh->rollback;
		    $dbh->disconnect;
		    $self->msg->error("Could not delete result");
		    return $self->redirect_to('results_list');
		}
	    }
	    $sth->finish;

	    foreach my $id (@{$form_data->{selection}}) {
		my $schema = "data_${id}";
		unless ($dbh->do(qq{DROP SCHEMA $schema CASCADE})) {
		    $dbh->rollback;
		    $dbh->disconnect;
		    $self->msg->error("Could not delete result data");
		    return $self->redirect_to('results_list');
		}
	    }

	    $self->msg->info("Result successfully removed");
	    $dbh->commit;
	    $dbh->disconnect;
	    return $self->redirect_to('results_list');
	}
    }

    # Retrieve data
    my $sth = $dbh->prepare(qq{SELECT r.id, r.set_name, r.description, to_char(r.upload_time, 'DD/MM/YYYY HH24:MI:SS TZ'), u.username
FROM results r
JOIN users u ON (r.id_owner = u.id)
ORDER BY r.upload_time DESC});
    $sth->execute();
    my $results = [ ];
    while (my ($i, $s, $d, $u, $o) = $sth->fetchrow()) {
	push @{$results}, { id => $i, set => $s, desc => $d, upload => $u, owner => $o };
    }

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(results => $results);

    $self->render;
}

sub upload {
    my $self = shift;

    # # Require admin privileges
    # if (! $self->perm->is_admin) {
    # 	return $self->render('unauthorized', status => 401);
    # }

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {

	my $tarball = $self->req->upload('tarball');

	my $result = { status => "success",
		       message => "File upload successful" };

	unless ($tarball) {
	    return $self->render_json({ status => "error",
					message => "Missing file to upload" });
	}

	# check the filename
	my $file = $tarball->filename;
	if ($file !~ m!\.tgz$!) {
	    return $self->render_json({ status => "error",
					message => "Expecting only .tgz files" });
	}

	# Prepare the workdir if needed
	my $destdir = $self->app->config->{upload}->{workdir};
	system("mkdir -p $destdir");
	if ($? >> 8) {
	    return $self->render_json({ status => "error",
					message => "Could not create work directory." });
	}

	$tarball->move_to("$destdir/$file");
	my $archive = "$destdir/$file";

	#
	my $form_data = $self->req->params->to_hash;
	my ($name, $desc);
	$name = $form_data->{name} if ($form_data->{name} !~ m/^\s*$/);
	$desc = $form_data->{desc} if ($form_data->{desc} !~ m/^\s*$/);

	# load the file
	my $dbh = $self->database;
	$Probe::Collector::dbh = $dbh;

	my $archive_dir;
	unless ($archive_dir = unpack_archive($archive, $destdir)) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    system("rm $archive");
	    return $self->render_json({ status => "error",
					message => "Unpack failed: ". $Probe::Collector::errstr });
	}

	my $meta_file = read_meta_file($archive_dir);
	unless ($meta_file = register_result_set($meta_file, $name, $desc, $self->session('user_id'))) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    system("rm $archive");
	    system("rm -rf $archive_dir");
	    return $self->render_json({ status => "error",
					message => "Result set registration failed: ". $Probe::Collector::errstr });
	}

	# Load each CSV file into the target table in the new
	# schema. load_csv_file() uses a savepoint and automatically
	# rolls back to it when the copy fails
	my @error = ();
	foreach my $f (<$archive_dir/*/*.csv>) {
	    unless (load_csv_file($meta_file, $f)) {
		push @error, qq{$f $Probe::Collector::errstr};
		next;
	    }
	}

	# Cleaning
	system("rm $archive");
	system("rm -rf $archive_dir");

	if (scalar(@error)) {
	    $result = { status => "warning",
			message => "Upload failed on: ".join(', ', @error) };
	}

	# Update the upload counter for the user when successful
	unless (update_counter($self->session('user_id'))) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->render_json({ status => "error",
					message => "Unable to update upload counter" });
	}

	$dbh->commit;
	$dbh->disconnect;

	return $self->render_json($result);
    }

    $self->render;
}

sub show {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;

    # Get the result details
    my $sth = $dbh->prepare(qq{SELECT r.set_name, r.description, to_char(r.upload_time, 'DD/MM/YYYY HH24:MI:SS TZ'), u.username
FROM results r
JOIN users u ON (r.id_owner = u.id)
WHERE r.id = ?});
    $sth->execute($id);
    my ($s, $d, $t, $o) = $sth->fetchrow();
    $sth->finish;
    if (defined $s) {
	$self->stash(result => { name => $s, desc => $d, upload => $t, owner => $o });
    } else {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found; # When the probe is not found, exit early
    }

    # Related probes
    $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, t.probe_type, p.description, p.min_version, p.max_version, p.enabled
FROM probes p
  JOIN probe_types t ON (p.probe_type = t.id)
  JOIN probes_in_sets i ON (p.id = i.id_probe)
WHERE i.id_result = ?
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute($id);

    my $probes = [ ];
    while (my ($i, $p, $t, $d, $mv, $xv, $e) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, probe => $p, type => $t, desc => $d,
			   min_version => $mv, max_version => $xv, enabled => $e };
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(probes => $probes);

    $self->render;
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	if (exists $form_data->{remove}) {
	    my $dbh = $self->database;
	    my $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets WHERE id_result = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not delete links to probes");
		return $self->redirect_to('results_show', id => $id);
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM report_contents WHERE id_result = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not delete links to reports");
		return $self->redirect_to('results_show', id => $id);
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM results WHERE id = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not delete result");
		return $self->redirect_to('results_show', id => $id);
	    }
	    $sth->finish;

	    my $schema = "data_${id}";
	    unless ($dbh->do(qq{DROP SCHEMA $schema CASCADE})) {
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not delete result data");
		return $self->redirect_to('results_show', id => $id);
	    }

	    $self->msg->info("Result successfully removed");
	    $dbh->commit;
	    $dbh->disconnect;
	    return $self->redirect_to('results_list');

	} else {
	    return $self->redirect_to('results_show', id => $id);
	}
    }

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT r.set_name, r.description, to_char(r.upload_time, 'DD/MM/YYYY HH24:MI:SS TZ'), u.username
FROM results r
JOIN users u ON (r.id_owner = u.id)
WHERE r.id = ?});
    $sth->execute($id);
    my ($s, $d, $t, $o) = $sth->fetchrow();
    $sth->finish;
    if (defined $s) {
	$self->stash(result => { name => $s, desc => $d, upload => $t, owner => $o });
    } else {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found; # When the probe is not found, exit early
    }

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

1;
