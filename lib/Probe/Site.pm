package Probe::Site;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub home {
  my $self = shift;

  # get the list of all schema
  my $dbh = $self->database;
  my $sth = $dbh->prepare("SELECT set_name, nsp_name, description FROM probe_sets ORDER BY upload_time DESC");
  $sth->execute();
  my $probes = [ ];
  while (my @row = $sth->fetchrow()) {
      push @{$probes}, { probe => $row[0], schema => $row[1], desc => $row[2] };
  }

  $sth->finish;
  $dbh->commit;
  $dbh->disconnect;

  $self->stash(probes => $probes);

  $self->render();
}

1;

