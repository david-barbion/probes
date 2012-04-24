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

    $self->render();
}

# sub add { }

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

    $self->render();

}

# sub edit { }
# sub remove { }

1;

