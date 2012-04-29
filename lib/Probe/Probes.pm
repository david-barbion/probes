package Probe::Probes;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT id, probe_name, description, version, enabled FROM probes ORDER BY 2});
    $sth->execute();
    my $probes = [ ];
    while (my ($i, $n, $d, $v, $e) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, probe_name => $n, description => $d,
			   version => $v, enabled => $e };
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
    my $sth = $dbh->prepare(qq{SELECT p.probe_name, t.probe_type, p.description, p.version, p.command, p.preload_command, p.target_ddl_query, p.source_path, p.enabled FROM probes p JOIN probe_types t ON (p.probe_type = t.id) WHERE p.id = ?});
    $sth->execute($id);

    my ($n, $t, $d, $v, $q, $pc, $dq, $sp, $e) = $sth->fetchrow();

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
			    version => $v,
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
	if ($form_data->{probe_version} eq '') {
            $self->msg->error("Empty target version");
            $e = 1;
        }
	if ($form_data->{source_path} eq '') {
            $self->msg->error("Empty path for input file in archive");
            $e = 1;
        }

        unless ($e) {
            my $rb = 0;
	    $sth = $dbh->prepare(qq{INSERT INTO probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING id});

	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_type},
						 $form_data->{probe_desc},
						 $form_data->{probe_version},
						 $form_data->{probe_query},
						 $form_data->{preload},
						 $form_data->{ddl_query},
						 $form_data->{source_path},
						 $form_data->{enable} ||= 0);

	    my ($id) = $sth->fetchrow();
	    $sth->finish;

	    if ($rb) {
		$self->msg->error("An error occured while saving. Action has been cancelled");
		$dbh->rollback;
	    } else {
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    # redirect
	    my $origin = $self->session->{origin} ||= 'probes_show';
            delete $self->session->{origin};
	    # XXX parameters in session
            return $self->redirect_to($origin, id => $id);

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
	if ($form_data->{probe_version} eq '') {
            $self->msg->error("Empty target version");
            $e = 1;
        }
	if ($form_data->{source_path} eq '') {
            $self->msg->error("Empty path for input file in archive");
            $e = 1;
        }

        unless ($e) {
            my $rb = 0;
	    $sth = $dbh->prepare(qq{UPDATE probes SET probe_name = ?, probe_type= ?, description = ?, version = ?, command = ?, preload_command = ?, target_ddl_query = ?, source_path = ?, enabled = ? WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_type},
						 $form_data->{probe_desc},
						 $form_data->{probe_version},
						 $form_data->{probe_query},
						 $form_data->{preload},
						 $form_data->{ddl_query},
						 $form_data->{source_path},
						 $form_data->{enable} ||= 0,
						 $id);
	    $sth->finish;

	    if ($rb) {
		$self->msg->error("An error occured while saving. Action has been cancelled");
		$dbh->rollback;
	    } else {
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    # redirect
	    my $origin = $self->session->{origin} ||= 'probes_show';
            delete $self->session->{origin};
	    # XXX parameters in session
            return $self->redirect_to($origin, id => $id);

	}
    }

    # Get probe info
    $dbh = $self->database;
    $sth = $dbh->prepare(qq{SELECT probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled FROM probes WHERE id = ?});
    $sth->execute($id);

    my ($n, $t, $d, $v, $q, $pc, $dq, $sp, $en) = $sth->fetchrow();

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

    # use controller params to preselected the checkbox only if not
    # already modifed (eg there was an error in the form)
    $self->param('enable', 'on') if ($en && !$e);

    # Same goes for the probe type
    $self->param('probe_type', $t) if (!$e);

    $self->stash(probe => { name => $n,
			    type => $t,
			    desc => $d,
			    version => $v,
			    query => $q,
			    preload => $pc,
			    ddlq => $dq,
			    path => $sp
			  });

    $self->render();
}

sub script {
    my $self = shift;

    my $e = 0;
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# Error processing
	unless (defined $form_data->{selection}) {
	    $self->msg->error("Nothing selected");
	    $e = 1;
	}

	unless ($e) {
	    my %ids;

	    if (ref $form_data->{selection} eq '') {
		$ids{$form_data->{selection}} = 1;
	    } else {
		%ids = map { $_ => 1 } @{$form_data->{selection}};
	    }

	    my $dbh = $self->database;
	    my $sth = $dbh->prepare(qq{SELECT p.probe_name, t.runner_key, p.command, p.source_path
FROM probes p JOIN probe_types t ON (p.probe_type = t.id)
WHERE p.enabled = true AND p.id = ?});
	    my $commands = [ ];
	    foreach my $id (keys %ids) {
		$sth->execute($id);
		my ($n, $t, $c, $p) = $sth->fetchrow();
		push @{$commands}, { id => $id,
				     probe => $n,
				     type => $t,
				     command => $c,
				     output => $p } if defined $n;
	    }
	    $sth->finish;
	    $dbh->commit;
	    $dbh->disconnect;

	    $Data::Dumper::Varname = "VAR";
	    $Data::Dumper::Purity = 1;
	    $self->stash(commands => Dumper($commands));

	    # Make the browser save the file with a proper filename
	    $self->tx->res->headers->header('Content-Disposition' => 'attachment; filename=probe_runner.pl');

	    return $self->render(template => 'script/probe_runner', format => 'pl');
	}
    }

    my $dbh = $self->database;
    # get the list of enabled probes
    my $sth = $dbh->prepare(qq{SELECT id, probe_name, probe_type, description, version FROM probes WHERE enabled = true ORDER BY 2, 3});
    $sth->execute;
    my $probes = [ ];
    while (my ($i, $n, $t, $d, $v) = $sth->fetchrow()) {
	push @{$probes}, { id => $i,
			   name => $n,
			   type => $t,
			   desc => $d,
			   version => $v
			 };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(probes => $probes);

    $self->render;
    # create a form to select the probes
    # generate the portion of the script
}

1;

