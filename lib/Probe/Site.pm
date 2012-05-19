package Probe::Site;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub home {
  my $self = shift;

  # get the list of all schema
  my $dbh = $self->database;
  my $sth = $dbh->prepare("SELECT id, set_name, nsp_name, description FROM probe_sets ORDER BY upload_time DESC");
  $sth->execute();
  my $sets = [ ];
  while (my @row = $sth->fetchrow()) {
      push @{$sets}, { id => $row[0], set => $row[1], schema => $row[2], desc => $row[3] };
  }

  $sth->finish;
  $dbh->commit;
  $dbh->disconnect;

  $self->stash(sets => $sets);

  # set redirection for the remove form
  $self->session->{origin} = 'home';

  $self->render();
}

sub upload {
    my $self = shift;

    my $tarball = $self->req->upload('tarball');

    unless ($tarball) {
	$self->msg->error("Missing file to upload");
	goto REDIRECT;
    }

    # move the file to the watchdir
    my $destdir = $self->app->config->{collector}->{watchdir};
    my $filename = $tarball->filename;
    if ($filename !~ m!\.tgz$!) {
	$self->msg->error("Expecting only .tgz files");
	goto REDIRECT;
    }

    $tarball->move_to("$destdir/$filename");

    $self->msg->info("File uploaded. Please wait for the collector to process it, it will be available soon");

  REDIRECT:
    my $origin = $self->session->{origin} ||= 'home';
    delete $self->session->{origin};
    return $self->redirect_to($origin);
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');
    my $dbh = $self->database;

    # Find the set to remove, check if it exists first
    my $sth = $dbh->prepare(qq{SELECT set_name, nsp_name, description FROM probe_sets WHERE id = ?});
    $sth->execute($id);
    my ($sn, $nsp, $sd) = $sth->fetchrow();
    $sth->finish;
    if (! defined $nsp) {
	$self->msg->error("Unable to find result set to remove");
	my $origin = $self->session->{origin} ||= 'home';
	delete $self->session->{origin};
	return $self->redirect_to($origin);
    }

    # Process the form
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Redirect if the cancel button has been pressed
	if (exists $form_data->{cancel}) {
	    my $origin = $self->session->{origin} ||= 'home';
	    delete $self->session->{origin};
	    return $self->redirect_to($origin);
	}

	# Each orphans graphs as an action and possibly a probe id,
	# the graph id is in the name of the radio button
	my $todo = { }; # { id => { action => link or remove, probe => id } }
	while (my ($k, $v) = each $form_data) {
	    if ($k =~ m/^action(\d+)$/) {
		$todo->{$1} = { } if (!exists $todo->{$1});
		$todo->{$1}->{action} = $v;
	    } elsif ($k =~ m/^probe(\d+)$/) {
		$todo->{$1} = { } if (!exists $todo->{$1});
		$todo->{$1}->{probe} = $v;
	    }
	}

	# Validate input, if the link action is chosen, a probe id
	# must be selected as well
	my $e = 0;
	while (my ($i, $d) = each $todo) {
	    if ($d->{action} eq 'link' && $d->{probe} eq '') {
		$e = 1;
		last;
	    }
	}

	if ($e) {
	    $self->msg->error("A probe must be selected when keeping a graph");
	} else {
	    # remove the schema
	    unless ($dbh->do(qq{DROP SCHEMA $nsp CASCADE})) {
		$dbh->rollback;
		$dbh->disconnect;

		$self->msg->error("Unable to remove the set: data");

		my $origin = $self->session->{origin} ||= 'home';
		delete $self->session->{origin};
		return $self->redirect_to($origin);
	    }

	    # remove the links to probes
	    $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets WHERE id_set = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;

		$self->msg->error("Unable to remove the set: linked probes");

		my $origin = $self->session->{origin} ||= 'home';
		delete $self->session->{origin};
		return $self->redirect_to($origin);
	    }
	    $sth->finish;

	    # remove the links to the graphs
	    $sth = $dbh->prepare(qq{DELETE FROM custom_graphs WHERE id_set = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;

		$self->msg->error("Unable to remove the set: saved graphs");

		my $origin = $self->session->{origin} ||= 'home';
		delete $self->session->{origin};
		return $self->redirect_to($origin);
	    }
	    $sth->finish;

	    # remove the line from probe_sets
	    $sth = $dbh->prepare(qq{DELETE FROM probe_sets WHERE id = ?});
	    unless ($sth->execute($id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;

		$self->msg->error("Unable to remove the set");

		my $origin = $self->session->{origin} ||= 'home';
		delete $self->session->{origin};
		return $self->redirect_to($origin);
	    }
	    $sth->finish;

	    # remove the custom graphs or link them to the chosen probes
	    my $rb = 0;
	    my $rm_graph = $dbh->prepare(qq{DELETE FROM graphs WHERE id = ?});
	    my $rm_options = $dbh->prepare(qq{DELETE FROM graphs_options WHERE id_graph = ?});
	    my $link_graph = $dbh->prepare(qq{INSERT INTO default_graphs (id_graph, id_probe) VALUES (?, ?)});
	    while (my ($i, $d) = each $todo) {
		if ($d->{action} eq 'remove') {
		    $rb = 1 unless defined $rm_options->execute($i);
		    $rb = 1 unless defined $rm_graph->execute($i);
		} elsif ($d->{action} eq 'link') {
		    $rb = 1 unless defined $link_graph->execute($i, $d->{probe});
		}
	    }
	    $rm_graph->finish;
	    $rm_options->finish;
	    $link_graph->finish;

	    if ($rb) {
		$self->msg->error("Unable to remove the set: graphs update");
		$dbh->rollback;
	    } else {
		$self->msg->info(qq{Result set "$sn" removed});
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    # redirect when done
	    my $origin = $self->session->{origin} ||= 'home';
	    delete $self->session->{origin};
	    return $self->redirect_to($origin);
	}
    }

    $self->stash(set => { name => $sn, desc => $sd });

    # We will have to remove the schema, line from probe_sets, lines
    # from probes_in_set, lines from custom graphs. Graphs that are
    # non defaut graphs may become orphans, the user input is asked on
    # what to do with them.

    # The list of probes is needed for the select choice
    $sth = $dbh->prepare("SELECT id, probe_name, version FROM probes");
    $sth->execute();
    my $probes = [ '' ];
    while (my @row = $sth->fetchrow()) {
	push @{$probes}, [ $row[1].'('.$row[2].')'  => $row[0] ];
    }
    $sth->finish;

    # Get the information of graphs that are only linked to the set
    $sth = $dbh->prepare(qq{SELECT cg.id_graph, g.graph_name, g.description, g.query
FROM custom_graphs cg
JOIN graphs g ON (g.id = cg.id_graph) 
LEFT JOIN default_graphs dg ON (dg.id_graph = g.id)
WHERE cg.id_set = ? AND dg.id_probe IS NULL});
    $sth->execute($id);
    my $graphs = [ ];
    while (my ($i, $n, $d, $q) = $sth->fetchrow()) {
	push @{$graphs}, { id => $i, name => $n, desc => $d, query => $q };
    }
    $sth->finish;

    $self->stash(graphs => $graphs);
    $self->stash(probes => $probes);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}
1;

