package Probe::Draw;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;

use Data::Dumper;

sub data {
    my $self = shift;

    my $nsp = $self->param('nsp');
    my $q = $self->param('query');

    my $dbh = $self->database;

    # Set the search to the schema contening the data tables
    $dbh->do("SET search_path TO public,${nsp}");

    # Get the results of the graph query
    my $sth = $dbh->prepare($q);
    $sth->execute();


    # Flot output
    # [ {
    #    "label": "serie",
    #    "data": [ [timestamp, valeur], ... ]
    #    },
    #    { ... }
    # ]

    my $points = { };
    # Group points together to form the serie
    while (my $hrow = $sth->fetchrow_hashref()) {
	foreach my $col (keys %{$hrow}) {
	    next if $col eq 'start_ts';
	    if (!exists($points->{$col})) {
		$points->{$col} = [ ];
	    }
	    push @{$points->{$col}}, [ $hrow->{'start_ts'}, $hrow->{$col} ];
	}
    }

    # Group the series data in a list of hashes: this what flot wants
    my $data = [ ];
    foreach my $s (keys %{$points}) {
	push @{$data}, { label => $s, data => $points->{$s} };
    }

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->render_json($data);
}

sub list {
    my $self = shift;

    my $nsp = $self->param('nsp');

    my $dbh = $self->database;

    # Get all the available graphs for the probes found in the chosen
    # probe set. Include whether the graph as already been selected
    # for the "show" page

    # Saved graphs
    my $sth = $dbh->prepare(qq{SELECT g.id, g.graph_name, g.description
FROM graphs g
JOIN custom_graphs cg ON (cg.id_graph = g.id)
JOIN probe_sets ps ON (ps.id = cg.id_set)
WHERE ps.nsp_name = ?});
    $sth->execute($nsp);

    my $saved_graphs = { };
    while (my @row = $sth->fetchrow()) {
	$saved_graphs->{$row[0]} = { id => $row[0],
				     name => $row[1],
				     desc => $row[2],
				     saved => 1,
				   };
    }
    $sth->finish;

    # All available graphs for the probe set
    $sth = $dbh->prepare(qq{SELECT g.id, g.graph_name, g.description
FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
WHERE ps.nsp_name = ?});
    $sth->execute($nsp);
    my $probe_graphs = { };
    while (my @row = $sth->fetchrow()) {
	$probe_graphs->{$row[0]} = { id => $row[0],
				    name => $row[1],
				    desc => $row[2],
				    saved => 0,
				   };
    }
    $sth->finish;

    # Merge the two here, since I could not quickly do that in a
    # single SQL request :/
    my $graphs = { };
    foreach my $r ($probe_graphs, $saved_graphs) {
	while (my ($k, $v) = each %{$r}) {
	    if (!exists $graphs->{$k} && $v->{saved}) {
		# graph is not linked to a probe, so it can be deleted from the list
		$v->{removable} = 1;
	    }
	    $graphs->{$k} = $v;
	}
    }

    $dbh->commit;
    $dbh->disconnect;

    my @list = sort { $a->{name} cmp $b->{name} }values %{$graphs};
    $self->stash(graphs => \@list);

    $self->render();
}

sub save_list {
    my $self = shift;

    my $nsp = $self->param('nsp');

    # input: liste d'id_graph, button submit
    # but: maj custom_graphs
    # recup listes de draw_list:
    # - choisir entre insert, ou delete
    # - si delete et orphelin:
    #   * prepare la liste des graphs orphelins
    #   * sauver la page de destination dans la session (helper ?)
    #   * envoyer à la page d'adoption par probe

    # Get all the available graphs for the probes found in the chosen
    # probe set. Include whether the graph as already been selected
    # for the "show" page

    my $dbh = $self->database;
    # Saved graphs
    my $sth = $dbh->prepare(qq{SELECT g.id
FROM graphs g
JOIN custom_graphs cg ON (cg.id_graph = g.id)
JOIN probe_sets ps ON (ps.id = cg.id_set)
WHERE ps.nsp_name = ?});
    $sth->execute($nsp);

    my $saved = { };
    while (my @row = $sth->fetchrow()) {
	$saved->{$row[0]} = 0;
    }
    $sth->finish;

    # All available graphs for the probe set
    $sth = $dbh->prepare(qq{SELECT g.id
FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
WHERE ps.nsp_name = ?});
    $sth->execute($nsp);

    my $probe = { };
    while (my @row = $sth->fetchrow()) {
	$probe->{$row[0]} = 1;
    }
    $sth->finish;

    my $form_data = $self->req->params->to_hash;
    my %selection = map { $_ => 1 } @{$form_data->{selection}};

    # Compare the submitted selection to the two lists to find
    # possible orphans when graphs are unselected
    my %merge;
    foreach my $r ($saved, $probe) {
	while (my ($k, $v) = each %{$r}) {
	    if (exists $merge{$k} && $v) {
		# saved graph is linked to a probe, it cannot become orphan
		$merge{$k} = 0;
	    } elsif (!exists $merge{$k} && !$v) {
		# this saved graph could become an orphan on deletion
		$merge{$k} = 1;
	    }
	}
    }

    # choose operation to perform to save the new list
    my $changes = { add => [ ], remove => [ ], orphans => [ ] };
    while (my ($k, $v) = each %merge) {
	if (!exists $selection{$k}) {
	    push @{$changes->{remove}}, $k;
	    push @{$changes->{orphans}}, $k if $v;
	} else {
	    delete $selection{$k};
	}
    }
    push @{$changes->{add}}, keys %selection;

    # If possible orphan graphs are found, ask the user input on what
    # to do with them
    if (scalar(@{$changes->{orphans}})) {
	$self->session->{draw_list_save_changes} = $changes;
	$self->session->{origin} = 'draw_list';

	return $self->redirect_to('draw_orphans', nsp => $nsp);
    }

    $sth = $dbh->prepare(qq{DELETE FROM custom_graphs
WHERE id_set = (SELECT id FROM probe_sets WHERE nsp_name = ?)
AND id_graph = ?});
    foreach my $id (@{$changes->{remove}}) {
	$sth->execute($nsp, $id);
    }
    $sth->finish;

    $sth = $dbh->prepare(qq{INSERT INTO custom_graphs (id_set, id_graph)
VALUES ((SELECT id FROM probe_sets WHERE nsp_name = ?), ?)});
    foreach my $id (@{$changes->{add}}) {
	$sth->execute($nsp, $id);
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    # Redirect depending on clicked button
    if (exists $form_data->{submit_save}) {
    	return $self->redirect_to('draw_list', nsp => $nsp);
    } else {
    	return $self->redirect_to('draw_show', nsp => $nsp);
    }
}

sub orphans {
    my $self = shift;

    my $nsp = $self->param('nsp');

    # Input can only come form the session, so redirect if it does not
    # contain something to process
    my $dlsc = $self->session->{draw_list_save_changes};
    if (!defined $dlsc) {
	$self->msg->info("Nothing to do");

	my $origin = $self->session->{origin} ||= 'draw_list';
	delete $self->session->{origin};

	return $self->redirect_to('draw_list', nsp => $nsp);
    }

    my $method = $self->req->method;

    if ($method =~ m/^POST$/i) {
	# process the input data
	my $form_data = $self->req->params->to_hash;

	# redirect if asked
	if (exists $form_data->{cancel}) {
	    my $origin = $self->session->{origin};

	    # cleanup session to ensure the user do not come back here
	    delete $self->session->{origin};
	    delete $self->session->{draw_list_save_changes};

	    return $self->redirect_to($origin, nsp => $nsp);
	}

	my $dest = { }; # { id => { action => link or remove, probe => id } }
	while (my ($k, $v) = each $form_data) {
	    if ($k =~ m/^action(\d+)$/) {
		$dest->{$1} = { } if (!exists $dest->{$1});
		$dest->{$1}->{action} = $v;
	    } elsif ($k =~ m/^probe(\d+)$/) {
		$dest->{$1} = { } if (!exists $dest->{$1});
		$dest->{$1}->{probe} = $v;
	    }
	}

	# validate input
	my $e = 0;
	while (my ($i, $d) = each $dest) {
	    if ($d->{action} eq 'link' && $d->{probe} eq '') {
		$self->msg->debug(qq{$i a=$d->{action}, p=$d->{probe}});
		$e = 1;
		last;
	    }
	}

	if ($e) {
	    $self->msg->error("A probe must be selected when keeping a graph");
	} else {
	    # do the whole save action
	    my $dbh = $self->database;

	    my $sth = $dbh->prepare(qq{DELETE FROM custom_graphs
WHERE id_set = (SELECT id FROM probe_sets WHERE nsp_name = ?)
AND id_graph = ?});
	    my $rb = 0;
	    foreach my $id (@{$dlsc->{remove}}) {
		$rb = 1 unless defined $sth->execute($nsp, $id);
	    }
	    $sth->finish;

	    $sth = $dbh->prepare(qq{INSERT INTO custom_graphs (id_set, id_graph)
VALUES ((SELECT id FROM probe_sets WHERE nsp_name = ?), ?)});
	    foreach my $id (@{$dlsc->{add}}) {
		$rb = 1 unless defined $sth->execute($nsp, $id);
	    }
	    $sth->finish;

	    my $rm_graph = $dbh->prepare(qq{DELETE FROM graphs WHERE id = ?});
	    my $rm_options = $dbh->prepare(qq{DELETE FROM graphs_options WHERE id_graph = ?});
	    my $link_graph = $dbh->prepare(qq{INSERT INTO default_graphs (id_graph, id_probe) VALUES (?, ?)});
	    while (my ($i, $d) = each $dest) {
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
		$self->msg->error("An error occured while saving. Action has been cancelled");
		$dbh->rollback;
	    } else {
		$dbh->commit;
	    }
	    $dbh->disconnect;

	    my $origin = $self->session->{origin};

	    # cleanup session to ensure the user do not come back here
	    delete $self->session->{origin};
	    delete $self->session->{draw_list_save_changes};

	    return $self->redirect_to($origin, nsp => $nsp);
	}
    }

    my $dbh = $self->database;

    # Get all the orphan graphs found in session
    my $in_list = join(', ', @{$dlsc->{orphans}});
    $in_list =~ s/[^\d, ]//g;
    unless ($in_list) {
	$self->msg->error("No orphans");
	$dbh->disconnect;
	return $self->redirect_to('draw_list', nsp => $nsp);
    }

    my $sth = $dbh->prepare(qq{SELECT id, graph_name, description, query FROM graphs WHERE id IN (${in_list})});
    $sth->execute();
    my $graphs = [ ];
    while (my @row = $sth->fetchrow()) {
	push @{$graphs}, { id => $row[0],
			   name => $row[1],
			   desc => $row[2],
			   query => $row[3] };
    }
    $sth->finish;

    # The list of probes is need for the select choice
    $sth = $dbh->prepare("SELECT id, probe_name, version FROM probes");
    $sth->execute();
    my $probes = [ '' ];
    while (my @row = $sth->fetchrow()) {
	push @{$probes}, [ $row[1].'('.$row[2].')'  => $row[0] ];
    }
    $sth->finish;

    $self->stash(graphs => $graphs);
    $self->stash(probes => $probes);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub show {
    my $self = shift;

    my $nsp = $self->param('nsp');


    my $dbh = $self->database;

    # there may be a form submission
    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {

	# we need the saved graph list to remove the unchecked ones
	my $sth = $dbh->prepare(qq{SELECT g.id
FROM graphs g
JOIN custom_graphs cg ON (cg.id_graph = g.id)
JOIN probe_sets ps ON (ps.id = cg.id_set)
WHERE ps.nsp_name = ?});
	$sth->execute($nsp);

	my $saved = { };
	while (my @row = $sth->fetchrow()) {
	    $saved->{$row[0]} = 0;
	}
	$sth->finish;

	# All available graphs for the probe set
	$sth = $dbh->prepare(qq{SELECT g.id
FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
WHERE ps.nsp_name = ?});
	$sth->execute($nsp);

	my $probe = { };
	while (my @row = $sth->fetchrow()) {
	    $probe->{$row[0]} = 1;
	}
	$sth->finish;

	my $form_data = $self->req->params->to_hash;
	my %selection = map { $_ => 1 } @{$form_data->{selection}};

	# Compare the submitted selection to the two lists to find
	# possible orphans when graphs are unselected
	my %merge;
	foreach my $r ($saved, $probe) {
	    while (my ($k, $v) = each %{$r}) {
		if (exists $merge{$k} && $v) {
		    # saved graph is linked to a probe, it cannot become orphan
		    $merge{$k} = 0;
		} elsif (!exists $merge{$k} && !$v) {
		    # this saved graph could become an orphan on deletion
		    $merge{$k} = 1;
		}
	    }
	}

	# choose operation to perform to save the new list
	my $changes = { add => [ ], remove => [ ], orphans => [ ] };
	while (my ($k, $v) = each %merge) {
	    if (!exists $selection{$k}) {
		push @{$changes->{remove}}, $k;
		push @{$changes->{orphans}}, $k if $v;
	    }
	}
	if (ref $form_data->{new_graphs} eq '') {
	    $changes->{add} = [ $form_data->{new_graphs} ];
	} else {
	    $changes->{add} = $form_data->{new_graphs};
	}

	# If possible orphan graphs are found, ask the user input on what
	# to do with them
	if (scalar(@{$changes->{orphans}})) {
	    $self->session->{draw_list_save_changes} = $changes;
	    $self->session->{origin} = 'draw_show';

	    return $self->redirect_to('draw_orphans', nsp => $nsp);
	}

	$sth = $dbh->prepare(qq{DELETE FROM custom_graphs
WHERE id_set = (SELECT id FROM probe_sets WHERE nsp_name = ?)
AND id_graph = ?});
	foreach my $id (@{$changes->{remove}}) {
	    $sth->execute($nsp, $id);
	}
	$sth->finish;

	$sth = $dbh->prepare(qq{INSERT INTO custom_graphs (id_set, id_graph)
VALUES ((SELECT id FROM probe_sets WHERE nsp_name = ?), ?)});
	foreach my $id (@{$changes->{add}}) {
	    $sth->execute($nsp, $id);
	}
	$sth->finish;

	$dbh->commit;

	# when the form is saved, the db is ready to give the new list
    }

    # Get the list of saved graphs
    my $sth = $dbh->prepare(qq{SELECT g.id, g.graph_name, g.description, g.query
FROM graphs g
JOIN custom_graphs cg ON (cg.id_graph = g.id)
JOIN probe_sets ps ON (ps.id = cg.id_set)
WHERE ps.nsp_name = ? ORDER BY 2});
    $sth->execute($nsp);

    # Get the list of default graphs for the select list in the update form
    my $def = $dbh->prepare(qq{SELECT g.id, g.graph_name
FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
WHERE ps.nsp_name = ?});
    $def->execute($nsp);

    my %defg = ( );
    while (my @row = $def->fetchrow()) {
	$defg{$row[0]} = $row[1];
    }
    $def->finish;

    # prepare to get the data from each graph query
    my $dbh_data = $self->database;
    $dbh_data->do("SET search_path TO public,${nsp}");
    my $json = Mojo::JSON->new;

    my $graphs = [ ];
    while (my @row = $sth->fetchrow()) {
	# get the data from the graph query
	my $sth_data = $dbh_data->prepare($row[3]);
	$sth_data->execute();

	my $points = { };
	# Group points together to form the serie
	while (my $hrow = $sth_data->fetchrow_hashref()) {
	    foreach my $col (keys %{$hrow}) {
		next if $col eq 'start_ts';
		if (!exists($points->{$col})) {
		    $points->{$col} = [ ];
		}
		push @{$points->{$col}}, [ $hrow->{'start_ts'}, $hrow->{$col} ];
	    }
	}

	$sth_data->finish;

	# Group the series data in a list of hashes: this what flot wants
	my $data = [ ];
	foreach my $s (keys %{$points}) {
	    push @{$data}, { label => $s, data => $points->{$s} };
	}

	my $json_data = $json->encode($data);

	# XXX Find the options of the graph

	# Merge everything into an item of the graph list
	push @{$graphs}, { id => $row[0], name => $row[1], desc => $row[2], data => $json_data };

	# remove the default graphs already selected from the select list
	delete $defg{$row[0]};
    }
    $sth->finish;

    $dbh_data->commit;
    $dbh_data->disconnect;

    $dbh->commit;
    $dbh->disconnect;

    # prepare the default graphs for the select_field teghelper
    my $new_graphs = [ ];
    while (my ($i, $n) = each %defg) {
	push @{$new_graphs}, [ $n => $i ];
    }

    $self->stash(new_graphs => $new_graphs);
    $self->stash(graphs => $graphs);

    $self->render();
}

sub add {
    my $self = shift;

    # find all available graphs for the set to fill presets
    my $q = qq{SELECT g.graph_name, g.query FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
LEFT JOIN custom_graphs cg ON (cg.id_graph = g.id and cg.id_set = ps.id)
WHERE ps.nsp_name = ? ORDER BY 2
};

    my $dbh = $self->database;
    my $sth = $dbh->prepare($q);
    $sth->execute($self->param('nsp'));

    # Input format for the select taghelper: %= select_field country => [[Germany => 'de'], 'en']
    # [ [ { option text => value } ], ... ]
    my $presets = [ '' ];
    while (my @row = $sth->fetchrow()) {
	my $option = [ $row[0] => $row[1] ];
	push @{$presets}, $option;
    }

    $sth->finish;

    # Get the list of probes for the select list in the save form
    $sth = $dbh->prepare("SELECT id, probe_name, version FROM probes");
    $sth->execute();

    my $probes = [ '' ];
    while (my @row = $sth->fetchrow()) {
	push @{$probes}, [ $row[1].'('.$row[2].')'  => $row[0] ];
    }

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(presets => $presets);
    $self->stash(probes => $probes);

    $self->render();
}

sub save_add {
    my $self = shift;

    # input: query, graph parameters (for later), saved_name, saved_desc, saved_probe, save (bouton)

    if (!defined($self->param('save'))) {
	return $self->redirect_to('draw_add', nsp => $self->param('nsp'));
    }

    my $nsp = $self->param('nsp');
    my $name = $self->param('saved_name');
    my $desc = $self->param('saved_desc');
    my $probe = $self->param('saved_probe');
    my $query = $self->param('query');

    unless ($name) {
	$self->msg->error('Unable to save graph, name is empty');
	return $self->redirect_to('draw_add', nsp => $self->param('nsp'));
    }

    my $dbh = $self->database;

    # add the new graph
    my $sth = $dbh->prepare("INSERT INTO graphs (graph_name, description, query) VALUES (?, ? , ?) RETURNING id");
    $sth->execute($name, $desc, $query);

    my @ret = $sth->fetchrow();
    $sth->finish;

    # select directly the graph for the current set
    $sth = $dbh->prepare("INSERT INTO custom_graphs (id_graph, id_set) VALUES (?, (SELECT id FROM probe_sets WHERE nsp_name = ?))");
    $sth->execute($ret[0], $nsp);

    # link the graph to the selected probe to make it available for everyone
    if ($probe) {
	$sth = $dbh->prepare("INSERT INTO default_graphs (id_graph, id_probe) VALUES (?, ?)");
	$sth->execute($ret[0], $probe);
    }

    $dbh->commit;
    $dbh->disconnect;

    return $self->redirect_to('draw_add', nsp => $self->param('nsp'));
}

sub edit {
    my $self = shift;

    my $nsp = $self->param('nsp');
    my $id = $self->param('id');
    my $form_data = { };

    # get the graph information to fill the form, with probe id when
    # the graph is default, this allow to preselect to proper probe in
    # saving div
    my $dbh = $self->database;
    my $sth = $dbh->prepare("SELECT g.graph_name, g.description, g.query, p.id
FROM graphs g
  LEFT JOIN default_graphs dg ON (dg.id_graph = g.id)
  LEFT JOIN probes p ON (p.id = dg.id_probe)
WHERE g.id = ?");
    $sth->execute($id);

    my @row = $sth->fetchrow();
    $sth->finish;

    $self->stash(graph_name => $row[0]);
    $self->stash(graph_desc => $row[1]);
    $self->stash(query => $row[2]);
    # Put the linked probe in a controller parameter so that it is
    # selected by the select_field tag helper in the template
    if (defined $row[3]) {
	$self->param('probe', $row[3]);
	$form_data->{graph_is_default} = 1;
	$form_data->{probe_id} = $row[3];
    } else  {
	$self->param('probe', '');
	$form_data->{graph_is_default} = 0;
	$form_data->{probe_id} = '';
    }

    # Get the default options and the graphs options and merge them to
    # set all the values of form inputs

    # default options
    $sth = $dbh->prepare(qq{SELECT option_name, default_value FROM flot_options});
    $sth->execute();

    my $default_options = { };
    while (my @row = $sth->fetchrow()) {
	$default_options->{$row[0]} = $row[1];
    }

    $sth->finish;

    # the graph options
    $sth = $dbh->prepare(qq{SELECT fo.option_name, go.option_value
FROM flot_options fo
  JOIN graphs_options go ON (go.id_option = fo.id)
  JOIN graphs g ON (go.id_graph = g.id) WHERE g.id = ?});
    $sth->execute($id);

    my $graph_options = { };
    while (my @row = $sth->fetchrow()) {
	$graph_options->{$row[0]} = $row[1];
    }

    $sth->finish;

    # merge them
    foreach my $r ($default_options, $graph_options) {
	while (my ($k, $v) = each %{$r}) {
	    $form_data->{$k} = $v;
	}
    }

    # Get the list of probes for the select list in the save form
    $sth = $dbh->prepare("SELECT id, probe_name, version FROM probes");
    $sth->execute();

    my $probes = [ '' ];
    while (my @row = $sth->fetchrow()) {
	push @{$probes}, [ $row[1].'('.$row[2].')'  => $row[0] ];
    }
    $form_data->{probes} = $probes;

    $form_data->{save_action} = 'sc';



    $self->stash(form_data => $form_data);

    # cleanup
    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub save_edit {
    my $self = shift;

    # Retrieve the parameters in a hashref, it contains all the form
    # data, it is better than $self->param which can't get multiple
    # selections for the same input name ; here we get an arrayref
    my $form_data = $self->req->params->to_hash;
    my $form_err = { };

    my $id = $self->param('id');
    my $nsp = $self->param('nsp');

    # Do all error checking on input fields
    my $err = 0;

    if ($form_data->{graph_name} eq '') {
	$self->msg->error("Empty Graph name");
	$form_err->{graph_name} = 1;
	$err = 1;
    }

    if ($form_data->{query} eq '') {
	$self->msg->error("Empty query");
	$form_err->{query} = 1;
	$err = 1;
    }

    if ($err) {
	$self->stash(form_err => $form_err);

	my $dbh = $self->database;
	# get the list of probes for the select
	my $sth = $dbh->prepare("SELECT id, probe_name, version FROM probes");
	$sth->execute();

	my $probes = [ '' ];
	while (my @row = $sth->fetchrow()) {
	    push @{$probes}, [ $row[1].' ('.$row[2].')' => $row[0] ];
	}
	$form_data->{probes} = $probes;
	$dbh->commit;
	$dbh->disconnect;

	$self->stash(form_data => $form_data);
	$self->stash(graph_name => $form_data->{graph_name});
	$self->stash(graph_desc => $form_data->{graph_desc});
	$self->stash(query => $form_data->{query});

	return $self->render(template => 'draw/edit');
    }

    my $dbh = $self->database;
    my $sth;
    # Process the form. There are 4 possible actions:
    # * Save the current graph (sc)
    # * Overwrite the default graph (ow)
    # * Save as a new graph (an)
    # * Create a new default graph for probe (and)


    if ($form_data->{save_action} eq 'sc') {
	# if it is a default graph, create a new graph and update the
	# custom_graphs link: do not ovewrite default here. Otherwise,
	# update graphs
	if ($form_data->{probe_id}) {
	    $sth = $dbh->prepare(qq{INSERT INTO graphs (graph_name, description, query) VALUES (?, ?, ?) RETURNING id});
	    $sth->execute($form_data->{graph_name},
			  $form_data->{graph_desc},
			  $form_data->{query});

	    my @row = $sth->fetchrow();
	    my $new_id = $row[0];
	    $sth->finish;

	    $sth = $dbh->prepare(qq{UPDATE custom_graphs SET id_graph = ? WHERE id_set = (SELECT id FROM probe_sets WHERE nsp_name = ?) AND id_graph = ?});
	    $sth->execute($new_id, $nsp, $id);
	    $sth->finish;

	    # replace the graph id to set the options later
	    $id = $new_id;
	} else {
	    $sth = $dbh->prepare(qq{UPDATE graphs SET graph_name = ?, description = ?, query = ? WHERE id = ?});
	    $sth->execute($form_data->{graph_name},
 			  $form_data->{graph_desc},
     			  $form_data->{query},
     			  $id);
     	    $sth->finish;
	}
    }

    if ($form_data->{save_action} eq 'ow') {
    	# overwrite the graph, update graphs
	$sth = $dbh->prepare(qq{UPDATE graphs SET graph_name = ?, description = ?, query = ? WHERE id = ?});
	$sth->execute($form_data->{graph_name},
		      $form_data->{graph_desc},
		      $form_data->{query},
		      $id);
	$sth->finish;
    }

    if ($form_data->{save_action} eq 'an') {
	# insert graph, add a custom link
	$sth = $dbh->prepare(qq{INSERT INTO graphs (graph_name, description, query) VALUES (?, ?, ?) RETURNING id});
	$sth->execute($form_data->{graph_name},
			  $form_data->{graph_desc},
			  $form_data->{query});

	    my @row = $sth->fetchrow();
	    my $new_id = $row[0];
	    $sth->finish;

	$sth = $dbh->prepare(qq{INSERT INTO custom_graphs (id_graph, id_set) VALUES (?, (SELECT id FROM probe_sets WHERE nsp_name = ?))});
	$sth->execute($new_id, $nsp);
	$sth->finish;

	# replace the graph id to set the options later
	$id = $new_id;
    }

    if ($form_data->{save_action} eq 'and') {
	# insert graph, add a custom link and a default link
	$sth = $dbh->prepare(qq{INSERT INTO graphs (graph_name, description, query) VALUES (?, ?, ?) RETURNING id});
	$sth->execute($form_data->{graph_name},
			  $form_data->{graph_desc},
			  $form_data->{query});

	my @row = $sth->fetchrow();
	my $new_id = $row[0];
	$sth->finish;

	$sth = $dbh->prepare(qq{INSERT INTO custom_graphs (id_graph, id_set) VALUES (?, (SELECT id FROM probe_sets WHERE nsp_name = ?))});
	$sth->execute($new_id, $nsp);
	$sth->finish;

	$sth = $dbh->prepare(qq{INSERT INTO default_graphs (id_graph, id_probe) VALUES (?, ?)});
	$sth->execute($new_id, $form_data->{probe});
	$sth->finish;

	# replace the graph id to set the options later
	$id = $new_id;
    }

    # Save the options: retrieve the default options and the current
    # options, then compare to the form data to only add/update non
    # default values

    # default options
    $sth = $dbh->prepare(qq{SELECT id, option_name, default_value FROM flot_options});
    $sth->execute();

    my %default_options = ();
    my %options_ids = ();
    while (my @row = $sth->fetchrow()) {
	$default_options{$row[1]} = $row[2];
	$options_ids{$row[1]} = $row[0];
    }
    $sth->finish;

    # the graph options
    $sth = $dbh->prepare(qq{SELECT fo.option_name, go.option_value
FROM flot_options fo
  JOIN graphs_options go ON (go.id_option = fo.id)
  JOIN graphs g ON (go.id_graph = g.id) WHERE g.id = ?});
    $sth->execute($id);

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
		    $upd->execute($form_data->{$opt}, $id, $options_ids{$opt});
		} elsif ($form_data->{$opt} eq $default_options{$opt}) {
		    $del->execute($id, $options_ids{$opt});
		}
	    } elsif ($form_data->{$opt} ne $default_options{$opt}) {
		# not in graph_options and non default value
		$ins->execute($id, $options_ids{$opt}, $form_data->{$opt});
	    }
	} elsif ($default_options{$opt} eq 'on') {
	    # 'off' checkboxes do not appear in form_data but default is 'on'
	    $ins->execute($id, $options_ids{$opt}, 'off');
	} else {
	    # delete checkbox values gone 'off'
	    $del->execute($id, $options_ids{$opt});
	}
    }
    $ins->finish;
    $upd->finish;
    $del->finish;

    $dbh->commit;
    $dbh->disconnect;

    return $self->redirect_to('draw_edit', nsp => $nsp, id => $id);
}

sub remove { }

1;
