package Probe::Reports;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;

    my $sth = $dbh->prepare(qq{SELECT r.id, r.report_name, r.description,
  string_agg(DISTINCT s.set_name, ', ' ORDER BY s.set_name),
  string_agg(DISTINCT g.graph_name, ', ' ORDER BY g.graph_name),
  u.username
FROM reports r
  JOIN report_contents c ON (r.id = c.id_report)
  JOIN results s ON (s.id = c.id_result)
  JOIN graphs g ON (g.id = c.id_graph)
  JOIN users u ON (r.id_owner = u.id)
GROUP BY r.id, r.report_name, r.description, u.username
ORDER BY r.report_name});
    $sth->execute;
    my $reports = [ ];
    while (my ($i, $n, $d, $r, $g, $o) = $sth->fetchrow) {
	push @{$reports}, { id => $i, name => $n, desc => $d,
			    results => $r, graphs => $g, owner => $o };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(reports => $reports);

    $self->render;
}

sub show {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;

    # Check if the graph
    my $sth = $dbh->prepare(qq{SELECT 1 FROM reports WHERE id = ?});
    $sth->execute($id);
    my ($res) = $sth->fetchrow;
    $sth->finish;
    if (! defined $res) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Get the list of graphs from the report
    $sth = $dbh->prepare(qq{SELECT g.id, g.graph_name, g.description, c.id_result
FROM graphs g
  JOIN report_contents c ON (g.id = c.id_graph)
  WHERE c.id_report = ?});
    $sth->execute($id);
    my $graphs = [ ];
    while (my ($i, $n, $d, $r) = $sth->fetchrow) {
	push @{$graphs}, { id => $i, name => $n,
			   desc => $d, nsp => 'data_'.$r };
    }
    $sth->finish;

    # Options
    $sth = $dbh->prepare(qq{SELECT p.option_name,
  coalesce(go.option_value, p.default_value)
FROM plot_options p
  LEFT JOIN (SELECT * from graphs_options where id_graph = ?) go ON (go.id_option = p.id)});
    $sth->finish;
    my $json = Mojo::JSON->new;
    foreach my $g (@{$graphs}) {
	$sth->execute($g->{id});
	my %options = ();
	while (my ($k, $v) = $sth->fetchrow()) {
	    $options{$k} = $v;
	}

	my $fo = { };
	while (my ($k, $v) = each %options) {
	    if ($k eq 'stacked' && $v eq 'on') {
		$fo->{_type_opts} = { } unless exists $fo->{_type_opts};
		$fo->{_type_opts}->{stacked} = Mojo::JSON->true;
	    }
	    elsif ($k eq 'legend-cols') {
		$fo->{legend} = { } unless exists $fo->{legend};
		$fo->{legend}->{noColumns} = $v;
	    }
	    elsif ($k eq 'series-width') {
		$fo->{_type_opts} = { } unless exists $fo->{_type_opts};
		$fo->{_type_opts}->{lineWidth} = $v;
	    }
	    elsif ($k eq 'show-legend' && $v eq 'on') {
		$fo->{legend} = { } unless exists $fo->{legend};
		$fo->{legend}->{container} = undef;
	    }
	    elsif ($k eq 'graph-type') {
		$fo->{_type} = $v;
	    }
	    elsif ($k eq 'filled' && $v eq 'on') {
		$fo->{_type_opts} = { } unless exists $fo->{_type_opts};
		$fo->{_type_opts}->{fill} = Mojo::JSON->true;
	    }
	}

	$fo->{_type_opts}->{show} = Mojo::JSON->true;

	# Specific display for pies: no grid and axis labels
	if ($fo->{_type} eq 'pie') {
	    $fo->{_type_opts}->{explode} = 10;
	    $fo->{grid} = { verticalLines => Mojo::JSON->false,
			    horizontalLines => Mojo::JSON->false };
	    $fo->{xaxis} = { showLabels => Mojo::JSON->false };
	    $fo->{yaxis} = { showLabels => Mojo::JSON->false };
	}

	# Move graph-type related options inside the porper branch
	$fo->{$fo->{_type}} = { } unless exists $fo->{$fo->{_type}};
	$fo->{$fo->{_type}} = $fo->{_type_opts};
	delete $fo->{_type_opts};
	delete $fo->{_type};

	$g->{options} = $json->encode($fo);
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(graphs => $graphs);

    $self->render;
}

sub add {
    my $self = shift;

    # Form submition
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Check form input, name and probes are mandatory. Action must be "save"
	if (!exists $form_data->{save}) {
	    return $self->redirect_to('reports_list');
	}


	my $e = 0;

	if ($form_data->{report_name} eq '') {
	    $self->msg->error("Empty report name");
	    $e = 1;
	}

	if ($form_data->{result} eq '') {
	    $self->msg->error("No data selected");
	    $e = 1;
	}

	if (!exists $form_data->{result}) {
	    $self->msg->error("No graph selected");
	    $e = 1;
	}

	unless ($e) {
	    my $rb = 0;
	    my $dbh = $self->database;
	    my $sth = $dbh->prepare(qq{INSERT INTO reports (report_name, description, id_owner)
VALUES (?, ?, ?) RETURNING id});
	    $rb = 1 unless defined $sth->execute($form_data->{report_name},
						 $form_data->{report_desc},
						 $self->session('user_id'));
	    my ($id) = $sth->fetchrow;
	    $sth->finish;

	    my @g;
	    if (ref $form_data->{selection} eq '') {
		@g = ($form_data->{selection});
	    } else {
		@g = @{$form_data->{selection}};
	    }

	    $sth = $dbh->prepare(qq{INSERT INTO report_contents (id_report, id_result, id_graph) VALUES (?, ?, ?)});
	    foreach my $graph (@g) {
		$rb = 1 unless defined $sth->execute($id, $form_data->{result}, $graph);
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
	    return $self->redirect_to('reports_show', id => $id);
	}
    }

    my $dbh = $self->database;

    # Get the list of results
    my $sth = $dbh->prepare(qq{SELECT id, set_name, description FROM results});
    $sth->execute;

    my $results = [ '' ];
    while (my ($i, $n, $d) = $sth->fetchrow) {
	push @{$results}, [ qq{$n ($d)} => $i ];
    }
    $sth->finish;

    # Get the list of possible graphs for each results
    $sth = $dbh->prepare(qq{SELECT r.id, array_agg(pg.id_graph order by pg.id_graph)
FROM results r
  JOIN probes_in_sets ps ON (r.id = ps.id_result)
  JOIN probe_graphs pg ON (ps.id_probe = pg.id_probe)
GROUP BY r.id});
    $sth->execute;

    my $gfilter = { };
    my $json = Mojo::JSON->new;
    while (my ($i, $g) = $sth->fetchrow) {
	$gfilter->{$i} = $json->encode($g);
    }
    $sth->finish;

    # Get the list of all graphs
    $sth = $dbh->prepare (qq{SELECT id, graph_name FROM graphs ORDER BY graph_name});
    $sth->execute;
    my $graphs = [ ];
    my $gall = [ ];
    while (my ($i, $n) = $sth->fetchrow) {
	push @{$graphs}, { id => $i, name => $n };
	push @{$gall}, $i;
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(results => $results);
    $self->stash(graphs => $graphs);
    $self->stash(gfilter => $gfilter);
    $self->stash(gall => $json->encode($gall));

    $self->render;
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');

    my $e = 0;

    # Form submition
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	my $form_data = $self->req->params->to_hash;

	# Check form input, name and probes are mandatory. Action must be "save"
	if (!exists $form_data->{save}) {
	    return $self->redirect_to('reports_list');
	}

	if ($form_data->{report_name} eq '') {
	    $self->msg->error("Empty report name");
	    $e = 1;
	}

	if ($form_data->{result} eq '') {
	    $self->msg->error("No data selected");
	    $e = 1;
	}

	if (!exists $form_data->{result}) {
	    $self->msg->error("No graph selected");
	    $e = 1;
	}

	unless ($e) {
	    my $rb = 0;
	    my $dbh = $self->database;

	    # Update the report details
	    my $sth = $dbh->prepare(qq{UPDATE reports SET report_name = ?, description = ?
WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($form_data->{report_name},
						 $form_data->{report_desc},
						 $id);
	    $sth->finish;

	    # Replace the report contents
	    $sth = $dbh->prepare(qq{DELETE FROM report_contents WHERE id_report = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    my @g = (ref $form_data->{selection} eq '') ? ($form_data->{selection}) : @{$form_data->{selection}};

	    $sth = $dbh->prepare(qq{INSERT INTO report_contents (id_report, id_result, id_graph) VALUES (?, ?, ?)});
	    foreach my $graph (@g) {
		$rb = 1 unless defined $sth->execute($id, $form_data->{result}, $graph);
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
	    return $self->redirect_to('reports_show', id => $id);
	}

    }

    my $dbh = $self->database;

    # Get the report details
    my $sth = $dbh->prepare(qq{SELECT r.id, r.report_name, r.description,
  array_agg(DISTINCT s.id),
  array_agg(DISTINCT g.id)
FROM reports r
  JOIN report_contents c ON (r.id = c.id_report)
  JOIN results s ON (s.id = c.id_result)
  JOIN graphs g ON (g.id = c.id_graph) WHERE r.id = ?
GROUP BY r.id, r.report_name, r.description});
    $sth->execute($id);
    my ($i, $n, $d, $r, $g) = $sth->fetchrow;
    $sth->finish;

    # Check if the report exist
    if (!defined $i) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Select the result and graph
    unless ($e) {
	$self->param('report_name', $n);
	$self->param('report_desc', $d);
	$self->param('result', $r->[0]); # XXX multiple results
    }

    # Prepare the graph current graph selection
    # XXX multiple results
    my $json = Mojo::JSON->new;
    $self->stash(gsel => $json->encode($g));

    # Get the results
    $sth = $dbh->prepare(qq{SELECT id, set_name, description FROM results});
    $sth->execute;

    my $results = [ '' ];
    while (my ($i, $n, $d) = $sth->fetchrow) {
	push @{$results}, [ qq{$n ($d)} => $i ];
    }
    $sth->finish;

    $self->stash(results => $results);

    # Get the list of possible graphs for each results
    $sth = $dbh->prepare(qq{SELECT r.id, array_agg(pg.id_graph order by pg.id_graph)
FROM results r
  JOIN probes_in_sets ps ON (r.id = ps.id_result)
  JOIN probe_graphs pg ON (ps.id_probe = pg.id_probe)
GROUP BY r.id});
    $sth->execute;

    my $gfilter = { };
    while (my ($i, $g) = $sth->fetchrow) {
	$gfilter->{$i} = $json->encode($g);
    }
    $sth->finish;

    # Get the graphs
    $sth = $dbh->prepare (qq{SELECT id, graph_name FROM graphs ORDER BY graph_name});
    $sth->execute;
    my $graphs = [ ];
    my $gall = [ ];
    while (my ($i, $n) = $sth->fetchrow) {
	push @{$graphs}, { id => $i, name => $n };
	push @{$gall}, $i;
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(graphs => $graphs);
    $self->stash(gfilter => $gfilter);
    $self->stash(gall => $json->encode($gall));
    $self->stash(error => $e);

    $self->render;
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

	    # Remove the report contents
	    my $sth = $dbh->prepare(qq{DELETE FROM report_contents WHERE id_report = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM reports WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($id);

	    if ($rb) {
		$self->msg->error("Could not remove the report");
		$dbh->rollback;
	    } else {
		$self->msg->info("Report successfully removed");
		$dbh->commit;
	    }
	    $dbh->disconnect;
	    return $self->redirect_to('reports_list');
	} else {
	    return $self->redirect_to('reports_show', id => $id);
	}
    }

    my $dbh = $self->database;

    # Get the report info like list, and check if it exists
    my $sth = $dbh->prepare(qq{SELECT r.id, r.report_name, r.description,
  string_agg(DISTINCT s.set_name, ', ' ORDER BY s.set_name),
  string_agg(DISTINCT g.graph_name, ', ' ORDER BY g.graph_name),
  u.username
FROM reports r
  JOIN report_contents c ON (r.id = c.id_report)
  JOIN results s ON (s.id = c.id_result)
  JOIN graphs g ON (g.id = c.id_graph)
  JOIN users u ON (r.id_owner = u.id)
WHERE r.id = ?
GROUP BY r.id, r.report_name, r.description, u.username});
    $sth->execute($id);

    my ($i, $n, $d, $r, $g, $o) = $sth->fetchrow;
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    if (! defined $i) {
	return $self->render_not_found;
    }

    $self->stash(report => { name => $n, desc => $d, results => $r,
			     graphs => $g, owner => $o });

    $self->render;
}

1;
