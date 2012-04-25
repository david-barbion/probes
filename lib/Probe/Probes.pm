package Probe::Probes;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;


sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare("SELECT id, probe_name, description, version FROM probes ORDER BY 2");
    $sth->execute();
    my $probes = [ ];
    while (my @row = $sth->fetchrow()) {
	push @{$probes}, { id => $row[0], probe_name => $row[1], description => $row[2],
			   version => $row[3] };
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
    my $sth = $dbh->prepare("SELECT probe_name, description, version, probe_query, ddl_query FROM probes WHERE id = ?");
    $sth->execute($id);

    my ($n, $d, $v, $pq, $dq) = $sth->fetchrow();

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    if (!defined $n) {
	$self->msg->error("Graph does not exist");

	my $origin = $self->session->{origin} ||= 'probes_list';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    $self->stash(probe => { name => $n,
			    desc => $d,
			    version => $v,
			    probeq => $pq,
			    ddlq => $dq });

    # set redirection for forms
    $self->session->{origin} = 'probes_show';

    $self->render();
}

sub add {
    my $self = shift;

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
        my $e = 0;
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_query} eq '') {
            $self->msg->error("Empty probe query");
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

        unless ($e) {
            my $dbh = $self->database;

            my $rb = 0;
	    my $sth = $dbh->prepare(qq{INSERT INTO probes (probe_name, description, version, probe_query, ddl_query) VALUES (?, ?, ?, ?, ?) RETURNING id});
	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_desc},
						 $form_data->{probe_version},
						 $form_data->{probe_query},
						 $form_data->{ddl_query});

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
        my $e = 0;
        if ($form_data->{probe_name} eq '') {
            $self->msg->error("Empty probe name");
            $e = 1;
        }
        if ($form_data->{probe_query} eq '') {
            $self->msg->error("Empty probe query");
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

        unless ($e) {
            my $dbh = $self->database;

            my $rb = 0;
	    my $sth = $dbh->prepare(qq{UPDATE probes SET probe_name = ?, description = ?, version = ?, probe_query = ?, ddl_query = ? WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($form_data->{probe_name},
						 $form_data->{probe_desc},
						 $form_data->{probe_version},
						 $form_data->{probe_query},
						 $form_data->{ddl_query},
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
    my $sth = $dbh->prepare("SELECT probe_name, description, version, probe_query, ddl_query FROM probes WHERE id = ?");
    $sth->execute($id);

    my ($n, $d, $v, $pq, $dq) = $sth->fetchrow();

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    if (!defined $n) {
	$self->msg->error("Graph does not exist");

	my $origin = $self->session->{origin} ||= 'probes_list';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    $self->stash(probe => { name => $n,
			    desc => $d,
			    version => $v,
			    probe_query => $pq,
			    ddl_query => $dq });

    $self->render();
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');

    
}

1;

