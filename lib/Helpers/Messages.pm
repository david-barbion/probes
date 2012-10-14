package Helpers::Messages;

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::ByteStream 'b';

has msg_lists => sub { { debug => [], info => [], error => [] } };

sub register {
    my ($self, $app) = @_;

    $app->helper(msg => sub { return $self; });

    $app->helper(
		 display_messages => sub {
		     my $html;

		     if (@{$self->msg_lists->{debug}}) {
			 $html .= qq{<ul class="messages_debug">\n};
			 $html .= join("\n", map { "<li>".$_."</li>" } @{$self->msg_lists->{debug}});
			 $html .= qq{</ul>};
		     }

		     if (@{$self->msg_lists->{error}}) {
			 $html .= qq{<ul class="messages_failure">\n};
			 $html .= join("\n", map { "<li>".$_."</li>" } @{$self->msg_lists->{error}});
			 $html .= qq{</ul>};
		     }

		     if (@{$self->msg_lists->{info}}) {
			 $html .= qq{<ul class="messages_success">\n};
			 $html .= join("\n", map { "<li>".$_."</li>" } @{$self->msg_lists->{info}});
			 $html .= qq{</ul>};
		     }

		     # Empty the message list so that it is displayed only once
		     $self->msg_lists({ debug => [], info => [], error => [] });

		     $html = ($html) ? qq{<div id="messages">$html</div>\n} : '';

		     return b($html);
		 }

		);

    return;
}

sub debug {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @debug = @{$messages->{debug}};
    push @debug, @_;
    $messages->{debug} = \@debug;
    $self->msg_lists($messages);
    return;
}

sub info {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @info = @{$messages->{info}};
    push @info, @_;
    $messages->{info} = \@info;
    $self->msg_lists($messages);
    return;
}

sub error {
    my $self = shift;

    my $messages = $self->msg_lists;
    my @error = @{$messages->{error}};
    push @error, @_;
    $messages->{error} = \@error;
    $self->msg_lists($messages);
    return;
}

sub save {
    return shift->msg_lists;
}

sub load {
    my $self = shift;
    $self->msg_lists(shift);
}

1;
