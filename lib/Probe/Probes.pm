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

    my $sth = $self->database;
    my $sth = $dbh->prepare("SELECT probe_name, description, version, probe_request FROM probes WHERE id = ?");
    $sth->execute($self->param('id'));
    my @row = $sth->fetchrow();

    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    $self->stash(probe => \@row);

    $self->render();

}

# sub edit { }
# sub remove { }

1;

