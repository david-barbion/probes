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

    # Get all the available graphs for the probes found in the chosen
    # probe set. Include whether the graph as already been selected
    # for the "show" page
    my $q = qq{SELECT g.id, g.graph_name, g.description, CASE WHEN cg.id_graph IS NULL THEN false ELSE true END AS saved FROM graphs g
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
    my $graphs = [ ];
    while (my @row = $sth->fetchrow()) {
	push @{$graphs}, { id => $row[0], name => $row[1], desc => $row[2],
			   saved => $row[3] };
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(graphs => $graphs);

    $self->render();
}

sub save_list {
    my $self = shift;

    # Maybe a button is too much here, a link would be straight
    # forward to the new graph page
    if ($self->param('dest') eq 'new') {
	return $self->redirect_to('draw_add', nsp => $self->param('nsp'));
    }

    my $param = $self->req->params->to_hash;

    # Save all the selected graphs
    my $dbh = $self->database;
    my $sth = $dbh->prepare("DELETE FROM custom_graphs WHERE id_set IN (SELECT id FROM probe_sets WHERE nsp_name = ?)");
    $sth->execute($self->param('nsp'));
    $sth->finish;

    $sth = $dbh->prepare("INSERT INTO custom_graphs (id_graph, id_set) VALUES (?, (SELECT id FROM probe_sets WHERE nsp_name = ?))");
    foreach my $id (@{$param->{selection}}) {
	$sth->execute($id, $self->param('nsp'));
    }
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    # Redirect based on clicked button
    if ($self->param('dest') eq 'update') {
	return $self->redirect_to('draw_list', nsp => $self->param('nsp'));
    } else {
	return $self->redirect_to('draw_show', nsp => $self->param('nsp'));
    }
}

sub show {
    my $self = shift;

    my $q = qq{SELECT g.id, g.graph_name, g.description, g.request
FROM graphs g
JOIN custom_graphs cg ON (cg.id_graph = g.id)
JOIN probe_sets ps ON (ps.id = cg.id_set)
WHERE ps.nsp_name = ? ORDER BY 2};

    my $nsp = $self->param('nsp');

    # Check if only one graph is asked or the whole list of selected graphs
    my $dbh = $self->database;
    my $sth = $dbh->prepare($q);
    $sth->execute($nsp);

    # prepare to get the data from each graph request
    my $dbh2 = $self->database;
    $dbh2->do("SET search_path TO public,${nsp}");
    my $json = Mojo::JSON->new;

    my $graphs = [ ];
    while (my @row = $sth->fetchrow()) {
	# get the data from the graph request
	my $sth_data = $dbh2->prepare($row[3]);
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

	push @{$graphs}, { id => $row[0], name => $row[1], desc => $row[2], data => $json_data };
    }
    $sth->finish;

    $dbh2->commit;
    $dbh2->disconnect;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(graphs => $graphs);

    $self->render();
}

sub add {
    my $self = shift;

    # find all available graphs for the set to fill presets
    my $q = qq{SELECT g.graph_name, g.request FROM graphs g
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
    my $sth = $dbh->prepare("INSERT INTO graphs (graph_name, description, request) VALUES (?, ? , ?) RETURNING id");
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

    # get the graph information to fill the form
    my $dbh = $self->database;
    my $sth = $dbh->prepare("SELECT graph_name, description, request FROM graphs WHERE id = ?");
    $sth->execute($id);

    my @row = $sth->fetchrow();
    $self->stash(graph_name => $row[0]);
    $self->stash(graph_desc => $row[1]);
    $self->stash(query => $row[2]);

    # get the graph options
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub save_edit {
    my $self = shift;

    my $form_data = $self->req->params->to_hash;

# $VAR1 = {
#           'graph_name' => 'bgwriter buffers',
#           'stacked' => 'on',
#           'serie-1' => 'on',
#           'query' => 'SELECT extract(epoch FROM datetime) AS start_ts,      
#   buffers_checkpoint - lag(buffers_checkpoint, 1) over () as buffers_checkpoint,
#   buffers_clean - lag(buffers_clean, 1) over () as buffers_clean,
#   buffers_backend - lag(buffers_backend, 1) over () as buffers_backend,
#   buffers_alloc - lag(buffers_alloc, 1) over () as buffers_alloc
# FROM bgwriter_stats
# ORDER BY 1;',
#           'serie-3' => 'on',
#           'legend-cols' => '1',
#           'series-width' => '1',
#           'serie-0' => 'on',
#           'save' => 'Save',
#           'graph_desc' => 'Activity rates on buffers by different parties',
#           'show-legend' => 'on',
#           'graph-type' => 'points',
#           'serie-2' => 'on',
#           'nsp' => 'adeo',
#           'filled' => 'on'
#         };

}

sub remove { }

1;
