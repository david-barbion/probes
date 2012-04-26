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
    my $sth = $dbh->prepare(qq{SELECT probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled FROM probes WHERE id = ?});
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

        # Error processing
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_type} eq '') {
            $self->msg->error("Empty probe type");
            $e = 1;
        }
	if ($form_data->{probe_type} =~ m/^SQL$/i and $form_data->{probe_query} eq '') {
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
            my $dbh = $self->database;

            my $rb = 0;
	    my $sth = $dbh->prepare(qq{INSERT INTO probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled)
VALUES (?, upper(?), ?, ?, ?, ?, ?, ?, ?) RETURNING id});

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

    $self->render();
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');

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

        # Error processing
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_type} eq '') {
            $self->msg->error("Empty probe type");
            $e = 1;
        }
	if ($form_data->{probe_type} =~ m/^SQL$/i and $form_data->{probe_query} eq '') {
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
            my $dbh = $self->database;

            my $rb = 0;
	    my $sth = $dbh->prepare(qq{UPDATE probes SET probe_name = ?, probe_type= ?, description = ?, version = ?, command = ?, preload_command = ?, target_ddl_query = ?, source_path = ?, enabled = ? WHERE id = ?});
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
    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled FROM probes WHERE id = ?});
    $sth->execute($id);

    my ($n, $t, $d, $v, $q, $pc, $dq, $sp, $en) = $sth->fetchrow();

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    if (!defined $n) {
	$self->msg->error("Probe does not exist");

	my $origin = $self->session->{origin} ||= 'probes_list';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    # use controller params to preselected the checkbox only if not
    # already modifed (eg there was an error in the form)
    $self->param('enable', 'on') if ($en && !$e);

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

# sub remove {
#     my $self = shift;

#     my $id = $self->param('id');

# }

1;

