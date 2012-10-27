package Probe::Site;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Probe::Collector;

sub home {
    my $self = shift;

    my $dbh = $self->database;

    # Get the list of scripts
    my $sth = $dbh->prepare(qq{SELECT id, script_name, description FROM scripts});
    $sth->execute;
    my $scripts = [ ];
    while (my ($i, $n, $d) = $sth->fetchrow) {
	push @{$scripts}, { id => $i, name => $n, desc => $d };
    }
    $sth->finish;

    $self->stash(scripts => $scripts);

    # Get the list of results
    $sth = $dbh->prepare(qq{SELECT id, set_name, description FROM results ORDER BY upload_time DESC LIMIT 5});
    $sth->execute();
    my $sets = [ ];
    while (my ($i, $s, $d) = $sth->fetchrow()) {
	push @{$sets}, { id => $i, set => $s, desc => $d };
    }
    $sth->finish;

    $self->stash(results => $sets);

    # Get the list of reports
    $sth = $dbh->prepare(qq{SELECT r.id, r.report_name, r.description,
  string_agg(DISTINCT g.graph_name, '<br />' ORDER BY g.graph_name)
FROM reports r
  JOIN report_contents c ON (r.id = c.id_report)
  JOIN graphs g ON (g.id = c.id_graph)
GROUP BY r.id, r.report_name, r.description
ORDER BY r.report_name LIMIT 5});
    $sth->execute;

    my $reports = [ ];
    while (my ($i, $n, $d, $g) = $sth->fetchrow) {
	push @{$reports}, { id => $i, name => $n, desc => $d, graphs => $g };
    }
    $sth->finish;

    $self->stash(reports => $reports);

    $dbh->commit;
    $dbh->disconnect;


    # set redirection for the remove form
    $self->session->{origin} = 'home';

    $self->render();
}

1;

