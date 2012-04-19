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

sub upload {
    my $self = shift;

    # First invocation, subscribe to "part" event to find the right one
    return $self->req->content->on(part => sub {
      my ($multi, $single) = @_;

      # Subscribe to "body" event of part to make sure we have all headers
      $single->on(body => sub {
        my $single = shift;

        # Make sure we have the right part and replace "read" event
        return unless $single->headers->content_disposition =~ /example/;
        $single->unsubscribe('read')->on(read => sub {
          my ($single, $chunk) = @_;

          # Log size of every chunk we receive
          $self->app->log->debug(length($chunk) . ' bytes uploaded.');
        });
      });
    }) unless $self->req->is_finished;

    $self->msg->info("Upload finished");

    # Second invocation, render response
    $self->render();
}

1;

