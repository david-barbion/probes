package Probe::Probes;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, p.min_version, p.max_version, p.enabled, t.probe_type, u.username
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
JOIN users u ON (p.id_owner = u.id)
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute();
    my $probes = [ ];
    while (my ($i, $n, $d, $iv, $av, $e, $t, $o) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, probe_name => $n, description => $d,
			   min_version => $iv, max_version => $av, enabled => $e,
			   type => $t, owner => $o };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(probes => $probes);

    # set redirection for forms
    $self->session->{origin} = 'probes_list';

    $self->render();
}

sub show {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT p.probe_name, t.probe_type, p.description, coalesce(p.min_version, 'None'),
  coalesce(p.max_version, 'None'), p.command, p.preload_command, p.target_ddl_query, p.source_path, p.enabled
FROM probes p
JOIN probe_types t ON (p.probe_type = t.id)
WHERE p.id = ?});
    $sth->execute($id);

    my ($n, $t, $d, $iv, $av, $q, $pc, $dq, $sp, $e) = $sth->fetchrow();

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    if (!defined $n) {
	$self->msg->error("Probe does not exist");

	my $origin = $self->session->{origin} ||= 'probes_list';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    $self->stash(probe => { name => $n,
			    type => $t,
			    desc => $d,
			    min_version => $iv,
			    max_version => $av,
			    query => $q,
			    preload => $pc,
			    ddlq => $dq,
			    path => $sp,
			    enabled => $e
			  });

    # set redirection for forms
    $self->session->{origin} = 'probes_show';

    $self->render();
}

sub add {
    my $self = shift;

    my $dbh = $self->database;
    my $sth;
    my $e = 0;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            my $origin = $self->session->{origin} ||= 'probes_list';
            delete $self->session->{origin};
	    # XXX parameters in session
            return $self->redirect_to($origin);
        }

	# We need to get the SQL probe type to check if a query must be given
	$sth = $dbh->prepare(qq{SELECT id FROM probe_types WHERE probe_type = 'SQL'});
	$sth->execute;
	my ($type) = $sth->fetchrow();
	$sth->finish;

        # Error processing
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_type} eq '') {
            $self->msg->error("Empty probe type");
            $e = 1;
        }
	if ($form_data->{probe_type} eq $type and $form_data->{probe_query} eq '') {
	    $self->msg->error("A query must be set when choosing SQL type");
	    $e = 1;
	}
	if ($form_data->{ddl_query} eq '') {
            $self->msg->error("Empty target table DDL query");
            $e = 1;
        }
	if ($form_data->{source_path} eq '') {
            $self->msg->error("Empty path for input file in archive");
            $e = 1;
        }

        unless ($e) {
            my $rb = 0;
	    $sth = $dbh->prepare(qq{INSERT INTO probes (probe_name, probe_type, description, min_version, max_version, command, preload_command, target_ddl_query, source_path, enabled, id_owner)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id});

	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_type},
						 $form_data->{probe_desc},
						 $form_data->{probe_min_version} ||= undef,
						 $form_data->{probe_max_version} ||= undef,
						 $form_data->{probe_query},
						 $form_data->{preload},
						 $form_data->{ddl_query},
						 $form_data->{source_path},
						 $form_data->{enable} ||= 0,
						 $self->session('user_id'));

	    my ($id) = $sth->fetchrow();
	    $sth->finish;

	    if ($rb) {
		if ($dbh->state eq '23505') { # Unique violation contraint on source_path
		    $self->msg->error("Path is in the archive must be unique. Action has been cancelled");
		} else {
		    $self->msg->error("An error occured while saving. Action has been cancelled");
		}
		$dbh->rollback;
	    } else {
		$self->msg->info("Probe created");
		$dbh->commit;
		$dbh->disconnect;
		return $self->redirect_to('probes_show', id => $id);
	    }

	}
    }

    # Get the list of probe_types for the select list in the form
    $sth = $dbh->prepare(qq{SELECT id, probe_type FROM probe_types ORDER BY id});
    $sth->execute;
    my $types = [ ];
    while (my ($i, $t) = $sth->fetchrow()) {
	push @{$types}, [ $t => $i ];
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(types => $types);

    $self->render();
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');
    my $dbh = $self->database;
    my $sth;
    my $e = 0;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            my $origin = $self->session->{origin} ||= 'probes_show';
            delete $self->session->{origin};
	    # XXX parameters in session
            return $self->redirect_to($origin, id => $id);
        }

	# We need to get the SQL probe type to check if a query must be given
	$sth = $dbh->prepare(qq{SELECT id FROM probe_types WHERE probe_type = 'SQL'});
	$sth->execute;
	my ($type) = $sth->fetchrow();
	$sth->finish;

        # Error processing
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_type} eq '') {
            $self->msg->error("Empty probe type");
            $e = 1;
        }
	if ($form_data->{probe_type} eq $type and $form_data->{probe_query} eq '') {
	    $self->msg->error("A query must be set when choosing SQL type");
	    $e = 1;
	}
	if ($form_data->{ddl_query} eq '') {
            $self->msg->error("Empty target table DDL query");
            $e = 1;
        }
	if ($form_data->{source_path} eq '') {
            $self->msg->error("Empty path for input file in archive");
            $e = 1;
        }

        unless ($e) {
            my $rb = 0;
	    $sth = $dbh->prepare(qq{UPDATE probes SET probe_name = ?, probe_type= ?, description = ?,
  min_version = ?, max_version = ?, command = ?, preload_command = ?,
  target_ddl_query = ?, source_path = ?, enabled = ?
WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_type},
						 $form_data->{probe_desc},
						 $form_data->{probe_min_version} ||= undef,
						 $form_data->{probe_max_version} ||= undef,
						 $form_data->{probe_query},
						 $form_data->{preload},
						 $form_data->{ddl_query},
						 $form_data->{source_path},
						 $form_data->{enable} ||= 0,
						 $id);
	    $sth->finish;

	    if ($rb) {
		if ($dbh->state eq '23505') { # Unique violation contraint on source_path
		    $self->msg->error("Path is in the archive must be unique. Action has been cancelled");
		} else {
		    $self->msg->error("An error occured while saving. Action has been cancelled");
		}
		$dbh->rollback;
	    } else {
		$dbh->commit;
		$dbh->disconnect;

		# redirect
		return $self->redirect_to('probes_show', id => $id);
	    }
	}
    }

    # Get probe info
    $dbh = $self->database;
    $sth = $dbh->prepare(qq{SELECT probe_name, probe_type, description, min_version, max_version, command, preload_command, target_ddl_query, source_path, enabled FROM probes WHERE id = ?});
    $sth->execute($id);

    my ($n, $t, $d, $iv, $av, $q, $pc, $dq, $sp, $en) = $sth->fetchrow();

    $sth->finish;

    if (!defined $n) {
	$self->msg->error("Probe does not exist");

	my $origin = $self->session->{origin} ||= 'probes_list';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    # Get the list of probe_types for the select list in the form
    $sth = $dbh->prepare(qq{SELECT id, probe_type FROM probe_types ORDER BY id});
    $sth->execute;
    my $types = [ ];
    while (my ($i, $t) = $sth->fetchrow()) {
	push @{$types}, [ $t => $i ];
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(types => $types);

    # use controller params to preselect the checkbox only if not
    # already modifed (eg there was an error in the form)
    $self->param('enable', 'on') if ($en && !$e);

    # Same goes for the probe type
    $self->param('probe_type', $t) if (!$e);

    $self->stash(probe => { name => $n,
			    type => $t,
			    desc => $d,
			    min_version => $iv,
			    max_version => $av,
			    query => $q,
			    preload => $pc,
			    ddlq => $dq,
			    path => $sp
			  });

    $self->render();
}


sub remove {
    my $self = shift;

    my $id = $self->param('id');

    my  $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	# process the input data
	my $form_data = $self->req->params->to_hash;

	# Redirect if cancel button has been pressed
	if (exists $form_data->{remove}) {

	    my $dbh = $self->database;
	    my $rb = 0;

	    # Remove graphs links
	    my $sth = $dbh->prepare(qq{DELETE FROM probe_graphs WHERE id_probe = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    # Remove results links
	    $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets WHERE id_probe = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    # Remove scripts links
	    $sth = $dbh->prepare(qq{DELETE FROM script_probes WHERE id_probe = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    # Remove the probe
	    $sth = $dbh->prepare(qq{DELETE FROM probes WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    if ($rb) {
		$self->msg->error("Could not remove the probe");
		$dbh->rollback;
	    } else {
		$self->msg->info("Probe successfully removed");
		$dbh->commit;
	    }
	    $dbh->disconnect;
	    return $self->redirect_to('probes_list');
	} else {
	    return $self->redirect_to('probes_show', id => $id);
	}
    }

    my $dbh = $self->database;

    # get the probe
    my $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, p.description, t.probe_type,
  p.min_version, p.max_version, p.command, p.preload_command, p.target_ddl_query,
  p.source_path, p.enabled,
  string_agg(DISTINCT r.set_name, ', ' ORDER BY r.set_name),
  string_agg(DISTINCT g.graph_name, ', ' ORDER BY g.graph_name),
  string_agg(DISTINCT s.script_name, ', ' ORDER BY s.script_name),
  u.username
FROM probes p
  JOIN probe_types t ON (t.id = p.probe_type)
  JOIN users u ON (p.id_owner = u.id)
  LEFT JOIN probes_in_sets pis ON (pis.id_probe = p.id)
  LEFT JOIN results r ON (r.id = pis.id_result)
  LEFT JOIN probe_graphs pg ON (pg.id_probe = p.id)
  LEFT JOIN graphs g ON (g.id = pg.id_graph)
  LEFT JOIN script_probes sp ON (sp.id_probe = p.id)
  LEFT JOIN scripts s ON (sp.id_script = s.id)
WHERE p.id = ?
GROUP BY p.id, p.probe_name, p.description, t.probe_type, u.username});
    $sth->execute($id);

    my ($i, $n, $d, $t, $iv, $av, $q, $pc, $dq, $sp, $e, $r, $g, $s, $o) = $sth->fetchrow;
    $sth->finish;

    # check if the probe exists
    if (! defined $i) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    $self->stash(probe => { name => $n,
			    desc => $d,
			    type => $t,
			    min_version => $iv,
			    max_version => $av,
			    query => $q,
			    preload => $pc,
			    ddlq => $dq,
			    path => $sp,
			    enabled => $e,
			    results => $r,
			    graphs => $g,
			    scripts => $s,
			    owner => $o
			  });

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

1;

