package Probe::Scripts;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

# /script
sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT s.id, s.script_name, s.description, u.username
FROM scripts s
JOIN users u ON (u.id = s.id_owner)});
    $sth->execute();
    my $scripts = [ ];
    while (my ($i, $n, $d, $o) = $sth->fetchrow()) {
	push @{$scripts}, { id => $i, name => $n, desc => $d, owner => $o };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(scripts => $scripts);

    $self->render();

}

# /script/:id
sub show {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;

    # Get the information on the script
    my $sth = $dbh->prepare(qq{SELECT s.script_name, s.description, u.username
FROM scripts s
JOIN users u ON (u.id = s.id_owner)
WHERE s.id = ?});
    $sth->execute($id);
    my ($n, $d, $o) = $sth->fetchrow;
    $sth->finish;

    if (! defined $n) {
	$self->msg->error("No such script");

	$dbh->commit;
	$dbh->disconnect;

	return $self->render_not_found;
    }

    $self->stash(script => { name => $n, desc => $d, owner => $o });


    # Get the included probes for the script
    $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, p.min_version, p.max_version, t.probe_type
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
JOIN script_probes s ON (s.id_probe = p.id)
WHERE p.enabled = true AND s.id_script = ?
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute($id);
    my $probes = [ ];
    while (my ($i, $n, $d, $iv, $av, $t) = $sth->fetchrow) {
	push @{$probes}, { id => $i, name => $n, desc => $d, min_vers => $iv, max_vers => $av, type => $t };
    }
    $sth->finish;

    $self->stash(probes => $probes);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

# /script/add
sub add {
    my $self = shift;

    my $dbh = $self->database;

    # Form submition
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Check form input, name and probes are mandatory. Action must be "save"
	if (!exists $form_data->{save}) {
	    return $self->redirect_to('scripts_list');
	}

	my $e = 0;

	if ($form_data->{script_name} eq '') {
	    $self->msg->error("Empty script name");
	    $e = 1;
	}

	if (! exists $form_data->{probes}) {
	    $self->msg->error("No probes selected");
	    $e = 1;
	}

	unless ($e) {
	    my $rb = 0;
	    my $sth = $dbh->prepare(qq{INSERT INTO scripts (script_name, description, id_owner)
VALUES (?, ?, ?) RETURNING id});
	    $rb = 1 unless defined $sth->execute($form_data->{script_name},
						 $form_data->{script_desc},
						 $self->session('user_id'));

	    my ($id) = $sth->fetchrow;
	    $sth->finish;

	    my @p;
	    if (ref $form_data->{probes} eq '') {
		@p = ($form_data->{probes});
	    } else {
		@p = @{$form_data->{probes}};
	    }

	    $sth = $dbh->prepare(qq{INSERT INTO script_probes (id_script, id_probe) VALUES (?, ?)});
	    foreach my $probe (@p) {
		$rb = 1 unless defined $sth->execute($id, $probe);
	    }
	    $sth->finish;

	    if ($rb) {
		$self->msg->error("An error occured while saving, action has been cancelled.");
		$dbh->rollback;
	    } else {
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    # Redirect to the details of the new script
	    return $self->redirect_to('scripts_show', id => $id);
	}
    }

    # Get the list of probes availables for selection
    my $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, p.min_version, p.max_version, t.probe_type
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
WHERE p.enabled = true
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute;
    my $probes = [ ];
    while (my ($i, $n, $d, $iv, $av, $t) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, name => $n, desc => $d, min_vers => $iv, max_vers => $av, type => $t };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(probes => $probes);

    $self->render();
}

# /script/:id/edit
sub edit {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;
    my $e = 0;

    # Form submition
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Check form input, name and probes are mandatory. Action must be "save"
	if (!exists $form_data->{save}) {
	    return $self->redirect_to('scripts_list');
	}

	if ($form_data->{script_name} eq '') {
	    $self->msg->error("Empty script name");
	    $e = 1;
	}

	if (! exists $form_data->{probes}) {
	    $self->msg->error("No probes selected");
	    $e = 1;
	}

	unless ($e) {
	    my $rb = 0;

	    # Update the script def
	    my $sth = $dbh->prepare(qq{UPDATE scripts SET script_name = ?, description = ? WHERE id = ?});
	    unless (defined $sth->execute($form_data->{script_name},
					  $form_data->{script_desc},
					  $id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not update script");
		return $self->redirect_to('scripts_list');
	    }
	    $sth->finish;

	    # Update the probe selection
	    $sth = $dbh->prepare(qq{DELETE FROM script_probes WHERE id_script = ?});
	    unless (defined $sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not update script on probe selection");
		return $self->redirect_to('scripts_list');
	    }

	    my @p;
	    if (ref $form_data->{probes} eq '') {
		@p = ($form_data->{probes});
	    } else {
		@p = @{$form_data->{probes}};
	    }

	    $sth = $dbh->prepare(qq{INSERT INTO script_probes (id_script, id_probe) VALUES (? ,?)});
	    foreach my $ip (@p) {
		unless (defined $sth->execute($id, $ip)) {
		    $sth->finish;
		    $dbh->rollback;
		    $dbh->disconnect;
		    $self->msg->error("Could not update script on probe selection");
		    return $self->redirect_to('scripts_list');
		}
	    }
	    $sth->finish;
	    $dbh->commit;
	    $dbh->disconnect;
	    $self->msg->info("Script successfully updated");
	    return $self->redirect_to('scripts_list');
	}
    }

    # Get the script data, and check if it exists.
    my $sth = $dbh->prepare(qq{SELECT script_name, description FROM scripts WHERE id = ?});
    $sth->execute($id);
    my ($n, $d) = $sth->fetchrow;
    $sth->finish;

    if (! defined $n) {
	$self->msg->error("Script does not exist");
	$dbh->commit;
	$dbh->disconnect;
	return $self->redirect_to('scripts_list');
    }

    # Pre-fill the form. Only overwrite the params when there where no
    # error in the validation of the input in the form
    unless ($e) {
	$self->param('script_name', $n);
	$self->param('script_desc', $d);
    }

    # Get the list of all probes.
    $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, p.min_version, p.max_version, t.probe_type
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
WHERE p.enabled = true
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute;
    my $probes = [ ];
    while (my ($i, $n, $d, $iv, $av, $t) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, name => $n, desc => $d, min_vers => $iv,
			   max_vers => $av, type => $t, saved => 0 };
    }
    $sth->finish;

    $self->stash(probes => $probes);

    # Get the list of selected probes for the script. Only pre-select
    # the checkbox when the submitted input is invalid
    unless ($e) {
	$sth = $dbh->prepare(qq{SELECT id_probe FROM script_probes WHERE id_script = ?});
	$sth->execute($id);

	my $p = [ ];
	while (my ($i) = $sth->fetchrow) {
	    push @{$p}, $i;
	}
	$sth->finish;

	# Pre-select the checkbox
	$self->param('probes', $p);
    }

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

# /script/:id/remove
sub remove {
    my $self = shift;

    my $id = $self->param('id');

    # First check if the target exists
    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT script_name, description
FROM scripts
WHERE id = ?});
    $sth->execute($id);
    my ($n, $d) = $sth->fetchrow;
    $sth->finish;

    if (! defined $n) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Process confirm form
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Action must be "remove", else redirect to the detail page XXX
	if (!exists $form_data->{remove}) {
	    $dbh->commit;
	    $dbh->disconnect;
	    return $self->redirect_to('scripts_show', id => $id);
	}

	unless (defined $dbh->do(qq{DELETE FROM script_probes WHERE id_script = $id;})) {
	    $self->msg->error("Unable to remove script");
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->redirect_to('scripts_list');
	}

	unless (defined $dbh->do(qq{DELETE FROM scripts WHERE id = $id;})) {
	    $self->msg->error("Unable to remove script");
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->redirect_to('scripts_list');
	}

	$self->msg->info("Script removed");
	$dbh->commit;
	$dbh->disconnect;
	return $self->redirect_to('scripts_list');
    }


    # Get the list of selected probes
    $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, p.min_version, p.max_version, t.probe_type
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
JOIN script_probes s ON (s.id_probe = p.id)
WHERE p.enabled = true AND s.id_script = ?
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute($id);
    my $probes = [ ];
    while (my ($i, $n, $d, $iv, $av, $t) = $sth->fetchrow) {
	push @{$probes}, { id => $i, name => $n, desc => $d, min_vers => $iv, max_vers => $av, type => $t };
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(script => { name => $n, desc =>$d });
    $self->stash(probes => $probes);

    $self->render;
}

sub download {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;

    # Check if the script exists
    my $sth = $dbh->prepare(qq{SELECT script_name FROM scripts WHERE id = ?});
    $sth->execute($id);
    my ($name) = $sth->fetchrow;
    $sth->finish;
    if (! defined $name) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Get all the probe data and generate the script
    $sth = $dbh->prepare(qq{SELECT p.probe_name, t.runner_key, p.command, p.min_version, p.max_version,
  p.preload_command, p.source_path
FROM probes p
  JOIN probe_types t ON (p.probe_type = t.id)
  JOIN script_probes s ON (p.id = s.id_probe)
WHERE p.enabled = true AND s.id_script = ?});
    $sth->execute($id);
    my $commands = { };
    while (my ($n, $t, $c, $iv, $av, $pc, $p) = $sth->fetchrow()) {
	$commands->{$t} = [ ] unless exists $commands->{$t};
	push @{$commands->{$t}}, { id => $id,
				   probe => $n,
				   command => $c,
				   min_version => $iv,
				   max_version => $av,
				   preload => $pc,
				   output => $p } if defined $n;
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $Data::Dumper::Varname = "VAR";
    $Data::Dumper::Purity = 1;
    $self->stash(commands => Dumper($commands));

    # Make the browser save the file with a proper filename
    $self->tx->res->headers->header('Content-Disposition' => "attachment; filename=probe_runner_${name}.pl");

    return $self->render(template => 'scripts/probe_runner', format => 'pl');
}

1;
