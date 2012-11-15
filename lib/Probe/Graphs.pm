package Probe::Graphs;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT g.id, g.graph_name, g.description,
  string_agg(p.probe_name, ', ' ORDER BY p.probe_name), u.username
FROM graphs g
  LEFT JOIN probe_graphs pg ON (g.id = pg.id_graph)
  LEFT JOIN probes p ON (pg.id_probe = p.id)
  JOIN users u ON (g.id_owner = u.id)
GROUP BY g.id, g.graph_name, g.description, u.username
ORDER BY g.graph_name});
    $sth->execute;
    my $graphs = [ ];
    while (my ($i, $n, $d, $p, $o) = $sth->fetchrow) {
	push @{$graphs}, { id => $i, name => $n, desc => $d,
			   probes => $p, owner => $o };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(graphs => $graphs);

    $self->render;
}

sub show {
    my $self = shift;

    my $id = $self->param('id');

    my $dbh = $self->database;
    # Get the details of the graph and check if it exists
    my $sth = $dbh->prepare(qq{SELECT g.graph_name, g.description, g.query, g.filter_query, u.username
FROM graphs g
  JOIN users u ON (g.id_owner = u.id)
WHERE g.id = ?});
    $sth->execute($id);
    my ($n, $d, $q, $fq, $o) = $sth->fetchrow;
    $sth->finish;
    if (! defined $n) {

	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    $self->stash(graph => { name => $n, desc => $d, owner => $o,
			    query => $q, filter_query => $fq });

    # Get the probes
    $sth = $dbh->prepare(qq{SELECT p.id, p.probe_name, t.probe_type, p.description, p.min_version, p.max_version, p.enabled
FROM probes p
  JOIN probe_types t ON (p.probe_type = t.id)
  JOIN probe_graphs pg ON (p.id = pg.id_probe)
WHERE pg.id_graph = ?
ORDER BY t.probe_type, p.probe_name, p.min_version DESC});
    $sth->execute($id);
    my $probes = [ ];
    while (my ($i, $p, $t, $d, $mv, $xv, $e) = $sth->fetchrow()) {
	push @{$probes}, { id => $i, probe => $p, type => $t, desc => $d,
			   min_version => $mv, max_version => $xv, enabled => $e };
    }
    $sth->finish;

    $self->stash(probes => $probes);

    # Get the reports
    $sth = $dbh->prepare(qq{SELECT r.id, r.report_name, r.description
FROM reports r
  JOIN report_contents rc ON (r.id = rc.id_report)
  JOIN graphs g ON (rc.id_graph = g.id)
WHERE g.id = ?
ORDER BY r.report_name});
    $sth->execute($id);
    my $reports = [ ];
    while (my ($i, $n, $d) = $sth->fetchrow) {
	push @{$reports}, { id => $i, name => $n, desc => $d };
    }
    $sth->finish;

    $self->stash(reports => $reports);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub add {
    my $self = shift;

    my $dbh = $self->database;
    my $e = 0;

    my  $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            my $origin = $self->session->{origin} ||= 'graphs_list';
            delete $self->session->{origin};
	    # XXX parameters in session
            return $self->redirect_to($origin);
        }

	# Mandatory fields
	if ($form_data->{graph_name} =~ m!^\s*$!s) {
            $self->msg->error("Empty graph name");
            $e = 1;
        }

	if ($form_data->{query} =~ m!^\s*$!s) {
	    $self->msg->error("Empty query");
            $e = 1;
        }

	# When there are placeholders inside the query, filter_query becomes mandatory
	if ($form_data->{query} =~ m!\?!s) {
	    if ($form_data->{filter_query} =~ m!^\s*$!s) {
		$self->msg->error("Empty filter query. Query has placeholders");
		$e = 1;
	    }
	}

	unless ($e) {
	    my $rb = 0;

	    # Add the graph
	    my $sth = $dbh->prepare(qq{INSERT INTO graphs (graph_name, description, query, yquery, filter_query, id_owner) VALUES (?, ?, ?, NULL, ?, ?) RETURNING id});
	    $rb = 1 unless defined $sth->execute($form_data->{graph_name},
						 $form_data->{graph_desc} || undef,
						 $form_data->{query},
						 $form_data->{filter_query} || undef,
						 $self->session('user_id'));
	    my ($id) = $sth->fetchrow;
	    $sth->finish;

	    # Add the plot options
	    $sth = $dbh->prepare(qq{SELECT id, option_name, default_value FROM plot_options});
	    $rb = 1 unless defined $sth->execute();
	    my %opt_values = ();
	    my %opt_ids = ();
	    while (my ($i, $o, $v) = $sth->fetchrow()) {
		$opt_values{$o} = $v;
		$opt_ids{$o} = $i;
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{INSERT INTO graphs_options (id_graph, id_option, option_value)
VALUES (?, ?, ?)});
	    foreach my $opt (keys %opt_values) {
		if (exists $form_data->{$opt}) {
		    if ($form_data->{$opt} ne $opt_values{$opt}) {
			$rb = 1 unless defined $sth->execute($id, $opt_ids{$opt}, $form_data->{$opt});
		    }
		} else {
		    # radio/checkboxes off with default being on
		    if ($opt_values{$opt} eq 'on') {
			$rb = 1 unless defined $sth->execute($id, $opt_ids{$opt}, 'off');
		    }
		}
	    }
	    $sth->finish;

	    # Link to the probes if asked
	    if (exists $form_data->{probe}) {
		my @p;
		if (ref $form_data->{probe} eq '') {
		    @p = ($form_data->{probe});
		} else {
		    @p = @{$form_data->{probe}};
		}

		$sth = $dbh->prepare(qq{INSERT INTO probe_graphs (id_graph, id_probe) VALUES (?, ?)});
		foreach my $probe (@p) {
		    $rb = 1 unless defined $sth->execute($id, $probe);
		}
		$sth->finish;
	    }

	    # Save
	    if ($rb) {
		$dbh->rollback;
		$self->msg->error("An error occured while saving. Action has been cancelled");
	    } else {
		$dbh->commit;
	    }

	    $dbh->disconnect;
	    return $self->redirect_to('graphs_list');
	}
    }

    # Get the list of results and corresponding schemas
    my $sth = $dbh->prepare(qq{SELECT id, set_name FROM results});
    $sth->execute;
    my $results = [ '' ];
    while (my ($i, $s) = $sth->fetchrow) {
	my $o = [ $s => "data_" . $i ];
	push @{$results}, $o;
    }
    $sth->finish;

    # Get the list of probes for the select list in the save form
    $sth = $dbh->prepare(qq{SELECT id, probe_name, min_version, max_version FROM probes ORDER BY probe_name});
    $sth->execute();

    my $probes = [ ];
    while (my ($i, $n, $iv, $av) = $sth->fetchrow()) {
	$iv = "any" unless defined $iv;
	$av = "any" unless defined $av;

	push @{$probes}, [ $n . ' ('.$iv.' - '. $av. ')'  => $i ];
    }
    $sth->finish;

    # Get the default options and make the preselections without
    # overwritting the controller params
    my $options = { };
    $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM plot_options});
    $sth->execute();
    while (my ($o, $v) = $sth->fetchrow()) {
	$options->{$o} = $v;
	next if ($v eq 'off'); # checkboxes and radios
	$self->param($o, $v) if !defined $self->param($o);
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(results => $results);
    $self->stash(probes => $probes);

    $self->render;
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');

    my $e = 0;

    my  $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	# process the input data
	my $form_data = $self->req->params->to_hash;

	# Redirect if cancel button has been pressed
	if (exists $form_data->{cancel}) {
	    return $self->redirect_to('graph_show', id => $id);
	}

 	# Mandatory fields
 	if ($form_data->{graph_name} =~ m!^\s*$!s) {
	    $self->msg->error("Empty graph name");
	    $e = 1;
	}

 	if ($form_data->{query} =~ m!^\s*$!s) {
 	    $self->msg->error("Empty query");
	    $e = 1;
	}

 	# When there are placeholders inside the query, filter_query becomes mandatory
 	if ($form_data->{query} =~ m!\?!s) {
 	    if ($form_data->{filter_query} =~ m!^\s*$!s) {
 		$self->msg->error("Empty filter query. Query has placeholders");
 		$e = 1;
 	    }
 	}

	unless ($e) {
	    my $rb = 0;

	    my $dbh = $self->database;

	    # Update the graph details
	    my $sth = $dbh->prepare(qq{UPDATE graphs SET graph_name = ?, description = ?, query = ?, filter_query = ? WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($form_data->{graph_name},
						 $form_data->{graph_desc},
						 $form_data->{query},
						 $form_data->{filter_query},
						 $id);
	    $sth->finish;

	    # Save the options: retrieve the default options and the current
	    # options, then compare to the form data to only add/update non
	    # default values

	    # default options
	    $sth = $dbh->prepare(qq{SELECT id, option_name, default_value FROM plot_options});
	    $rb = 1 unless defined $sth->execute();

	    my %default_options = ();
	    my %options_ids = ();
	    while (my @row = $sth->fetchrow()) {
		$default_options{$row[1]} = $row[2];
		$options_ids{$row[1]} = $row[0];
	    }
	    $sth->finish;

	    # the graph options
	    $sth = $dbh->prepare(qq{SELECT po.option_name, go.option_value
FROM plot_options po
  JOIN graphs_options go ON (go.id_option = po.id)
  JOIN graphs g ON (go.id_graph = g.id) WHERE g.id = ?});
	    $rb = 1 unless defined $sth->execute($id);

	    my %graph_options = ();
	    while (my @row = $sth->fetchrow()) {
		$graph_options{$row[0]} = $row[1];
	    }
	    $sth->finish;

	    # Prepare the three possible statements
	    my $ins = $dbh->prepare(qq{INSERT INTO graphs_options (id_graph, id_option, option_value) VALUES (?, ?, ?)});
	    my $upd = $dbh->prepare(qq{UPDATE graphs_options SET option_value = ? WHERE id_graph = ? AND id_option = ?});
	    my $del = $dbh->prepare(qq{DELETE FROM graphs_options WHERE id_graph = ? AND id_option = ?});
	    foreach my $opt (keys %default_options) {
		if (defined $form_data->{$opt}) { # option is set in form
		    if (defined $graph_options{$opt}) { # option is local to graph
			if ($form_data->{$opt} ne $graph_options{$opt}
			    and $form_data->{$opt} ne $default_options{$opt}) {
			    $rb = 1 unless defined $upd->execute($form_data->{$opt}, $id, $options_ids{$opt});
			} elsif ($form_data->{$opt} eq $default_options{$opt}) {
			    $rb = 1 unless defined $del->execute($id, $options_ids{$opt});
			}
		    } elsif ($form_data->{$opt} ne $default_options{$opt}) {
			# not in graph_options and non default value
			$rb = 1 unless defined $ins->execute($id, $options_ids{$opt}, $form_data->{$opt});
		    }
		} elsif ($default_options{$opt} eq 'on') {
		    # 'off' checkboxes do not appear in form_data but default is 'on' and 
		    if (! exists $graph_options{$opt}) {
			$rb = 1 unless defined $ins->execute($id, $options_ids{$opt}, 'off');
		    } elsif ($graph_options{$opt} eq 'on') {
			$rb = 1 unless defined $upd->execute('off', $id, $options_ids{$opt});
		    }
		} else {
		    # delete checkbox values gone 'off'
		    $rb = 1 unless defined $del->execute($id, $options_ids{$opt});
		}
	    }
	    $ins->finish;
	    $upd->finish;
	    $del->finish;

	    # Update the link to the probe
	    $sth = $dbh->prepare(qq{DELETE FROM probe_graphs WHERE id_graph = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    if (exists $form_data->{probe}) {
		my @p;
		if (ref $form_data->{probe} eq '') {
		    @p = ($form_data->{probe});
		} else {
		    @p = @{$form_data->{probe}};
		}

		$sth = $dbh->prepare(qq{INSERT INTO probe_graphs (id_graph, id_probe) VALUES (?, ?)});
		foreach my $probe (@p) {
		    $rb = 1 unless defined $sth->execute($id, $probe);
		}
		$sth->finish;
	    }

	    if ($rb) {
		$self->msg->error("An error occured while saving. Action has been cancelled");
		$dbh->rollback;
	    } else {
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    return $self->redirect_to('graphs_show', id => $id);
	}
    }

    my $dbh = $self->database;
    # Get the graph details, and check if it exists
    my $sth = $dbh->prepare(qq{SELECT g.graph_name, g.description, g.query, g.filter_query,
  array_agg(pg.id_probe)
FROM graphs g
  LEFT JOIN probe_graphs pg ON (g.id = pg.id_graph)
WHERE id = ?
GROUP BY g.graph_name, g.description, g.query, g.filter_query});
    $sth->execute($id);
    my ($n, $d, $q, $fq, $p) = $sth->fetchrow;
    $sth->finish;
    if (! defined $n) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Probes with selection, to pre-fill the select
    $sth = $dbh->prepare(qq{SELECT id, probe_name, min_version, max_version FROM probes ORDER BY probe_name});
    $sth->execute();

    my $probes = [ ];
    while (my ($i, $n, $iv, $av) = $sth->fetchrow()) {
	$iv = "any" unless defined $iv;
	$av = "any" unless defined $av;

	push @{$probes}, [ $n . ' ('.$iv.' - '. $av. ')'  => $i ];
    }
    $sth->finish;
    $self->stash(probes => $probes);

    # Options
    my $options = { };
    # default options
    $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM plot_options});
    $sth->execute();
    while (my ($o, $v) = $sth->fetchrow()) {
	$options->{$o} = $v;
    }
    $sth->finish;

    # overwrite with the graph options
    $sth = $dbh->prepare(qq{SELECT po.option_name, go.option_value
FROM plot_options po
  JOIN graphs_options go ON (go.id_option = po.id)
  JOIN graphs g ON (go.id_graph = g.id) WHERE g.id = ?});
    $sth->execute($id);
    while (my ($o, $v) = $sth->fetchrow()) {
	$options->{$o} = $v;
    }
    $sth->finish;

    # Results for the preview
    $sth = $dbh->prepare(qq{SELECT id, set_name FROM results});
    $sth->execute;
    my $results = [ '' ];
    while (my ($i, $s) = $sth->fetchrow) {
	my $o = [ $s => "data_" . $i ];
	push @{$results}, $o;
    }
    $sth->finish;

    $self->stash(results => $results);

    # Pre-fill the form without overwriting user input on validation
    # errors
    unless ($e) {
	$self->param('graph_name', $n);
	$self->param('graph_desc', $d);
	$self->param('query', $q);
	$self->param('filter_query', $fq);
	$self->param('probe', $p) if (defined $p);
	$self->param('graph-type', $options->{'graph-type'});
	foreach my $o ('stacked', 'filled', 'show-legend') {
	    $self->param($o, 'on') if ($options->{$o} eq 'on' && !$e);
	}
	$self->param('series-width', $options->{'series-width'});
	$self->param('legend-cols',$options->{'legend-cols'});
    }



    $dbh->commit;
    $dbh->disconnect;

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

	    # Remove the links to probes and plot_options
	    my $sth = $dbh->prepare(qq{DELETE FROM probe_graphs WHERE id_graph = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    $sth = $dbh->prepare(qq{DELETE FROM graphs_options WHERE id_graph = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    # Remove the graph
	    $sth = $dbh->prepare(qq{DELETE FROM graphs WHERE id = ?});
	    $rb = 1 unless defined $sth->execute($id);
	    $sth->finish;

	    if ($rb) {
		$self->msg->error("Could not remove the graph");
		$dbh->rollback;
	    } else {
		$self->msg->info("Graph successfully removed");
		$dbh->commit;
	    }
	    $dbh->disconnect;
	    return $self->redirect_to('graphs_list');

	} else {
	    return $self->redirect_to('graphs_show', id => $id);
	}

    }

    my $dbh = $self->database;

    # Get the graph detail and check if it exists
    my $sth = $dbh->prepare(qq{SELECT g.graph_name, g.description, g.query,
  string_agg(p.probe_name, ', ' ORDER BY p.probe_name), u.username
FROM graphs g
  LEFT JOIN probe_graphs pg ON (g.id = pg.id_graph)
  LEFT JOIN probes p ON (pg.id_probe = p.id)
  JOIN users u ON (g.id_owner = u.id)
WHERE g.id = ?
GROUP BY g.graph_name, g.description, g.query, u.username});

    $sth->execute($id);
    my ($n, $d, $q, $p, $o) = $sth->fetchrow;
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    if (! defined $n) {
	return $self->render_not_found;
    }

    $self->stash(graph => { name => $n, desc => $d, query => $q,
			    probes => $p, owner => $o });

    # Recupérer la liste des rapports

    $self->render;
}

sub data {
    my $self = shift;

    my $nsp = $self->param('namespace');
    my $q = $self->param('query');
    my $id_graph = $self->param('id');
    my $fq = $self->param('filter_query');;

    if ($nsp =~ m!^\s*$!s) {
	return $self->render_json({ error => "results data are not defined" });
    }

    my $dbh = $self->database;

    # Set the search to the schema contening the data tables
    $dbh->do("SET search_path TO public,${nsp}");

    # When we get an id on input, retrive the query
    if (defined $id_graph) {
	my $sth = $dbh->prepare(qq{SELECT query, filter_query FROM graphs WHERE id = ?});
	$sth->execute($id_graph);
	($q, $fq) = $sth->fetchrow();
	$sth->finish;
    }

    if (!defined $q or $q =~ m!^\s*$!s) {
	$dbh->rollback;
    	$dbh->disconnect;
    	return $self->render_json({ error => "query is not defined" });
    }

    my $data = [];
    if ($q =~ m!\?!s) {

	# There are place holders in the query
	if (defined $fq and $fq =~ m!^\s*$!s) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->render_json({ error => "empty filter query" });
	}

	my $sth = $dbh->prepare($fq);
	unless ($sth->execute()) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->render_json({ error => "filter query execution failed" });
	}

	my $filters = [];
	while (my @row = $sth->fetchrow()) {
	    push @{$filters}, \@row;
	}
	$sth->finish;

	foreach my $f (@{$filters}) {
	    $sth = $dbh->prepare($q);
	    unless ($sth->execute(@{$f})) {
		$dbh->rollback;
		$dbh->disconnect;
		return $self->render_json({ error => "query execution failed" });
	    }

	    my $points = { };
	    # Group points together to form the serie
	    while (my $hrow = $sth->fetchrow_hashref()) {
		foreach my $col (keys %{$hrow}) {
		    next if ($col eq 'stat_ts');

		    # The x axis must be named stat_ts in the query
		    if (!exists($points->{$col})) {
			$points->{$col} = [ ];
		    }
		    next if ! defined $hrow->{$col} || ! defined $hrow->{'stat_ts'};
		    push @{$points->{$col}}, [ int($hrow->{'stat_ts'}), $hrow->{$col} * 1.0 ];
		}
	    }
	    $sth->finish;

	    # Group the series data in a list of hashes: this what flot wants
	    my $series = [ ];
	    foreach my $s (keys %{$points}) {
		push @{$series}, { label => $s, data => $points->{$s} };
	    }

	    push @{$data}, { filters => $f, series => $series };
	}
    } else {

	# Get the results of the graph query
	my $sth = $dbh->prepare($q);
	unless ($sth->execute()) {
	    $dbh->rollback;
	    $dbh->disconnect;
	    return $self->render_json({ error => "query execution failed" });
	}

	# Flotr2 input:
	# [ { "label": "serie", "data": [ [timestamp, valeur], ... ] },
	#   { ... } ]

	my $points = { };
	# Group points together to form the serie
	while (my $hrow = $sth->fetchrow_hashref()) {
	    foreach my $col (keys %{$hrow}) {
		# Flotr2 has issues with the autoscale feature, so we
		# compute the min and max values of the two axis and
		# hardcode them in the graph options
		next if ($col eq 'stat_ts');

		# The x axis must be named stat_ts in the query
		if (!exists($points->{$col})) {
		    $points->{$col} = [ ];
		}
		next if ! defined $hrow->{$col} || ! defined $hrow->{'stat_ts'};
		push @{$points->{$col}}, [ int($hrow->{'stat_ts'}), $hrow->{$col} * 1.0 ];
	    }
	}

	# Group the series data in a list of hashes: this what flot wants
	my $series = [ ];
	foreach my $s (keys %{$points}) {
	    push @{$series}, { label => $s, data => $points->{$s} };
	}

	push @{$data}, { filters => Mojo::JSON->false, series => $series };
	$sth->finish;
    }


    $dbh->commit;
    $dbh->disconnect;

    $self->render_json($data);
}

sub options_list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM plot_options});
    $sth->execute;
    my $options = { };
    while (my ($o, $v) = $sth->fetchrow) {
	$options->{$o} = $v;
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(options => $options);

    $self->render;
}

sub options_edit {
    my $self = shift;

    my $method = $self->req->method;

    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            return $self->redirect_to('graphs_options_list');
        }

	my $dbh = $self->database;

	# Get the current values. Checkboxes that are no longer checked
	# do not appear in the submited data: we need to check if the
	# corresponding option should be updated
	my $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM plot_options});
	$sth->execute;
	my $options = { };
	while (my ($o, $v) = $sth->fetchrow) {
	    $options->{$o} = $v;
	}
	$sth->finish;

	$sth = $dbh->prepare(qq{UPDATE plot_options SET default_value = ? WHERE option_name = ?});

	# Take care of the checkboxes
	foreach my $opt (qw/stacked filled show-legend/) {
	    # checkbox goes from 'off' to 'on'
	    if (exists $form_data->{$opt} && $options->{$opt} eq 'off') {
		$sth->execute('on', $opt);
	    }

	    # checkbox goes from 'on' to 'off'
	    if (! exists $form_data->{$opt} && $options->{$opt} eq 'on') {
		$sth->execute('off', $opt);
	    }
	}

	# Update the other options
	foreach my $opt (qw/graph-type legend-cols series-width/) {
	    # Only update if the value has changed
	    if ($form_data->{$opt} ne $options->{$opt}) {
		$sth->execute($form_data->{$opt}, $opt);
	    }
	}

	$sth->finish;
	$dbh->commit;
	$dbh->disconnect;

	return $self->redirect_to('graphs_options_list');

    } else {

	my $dbh = $self->database;
	my $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM plot_options});
	$sth->execute;
	while (my ($o, $v) = $sth->fetchrow) {
	    # Put each value inside the page parameter, so that values
	    # are set in the form
	    $self->param($o, $v);
	}
	$sth->finish;

	$dbh->commit;
	$dbh->disconnect;
    }

    $self->render;
}

1;
