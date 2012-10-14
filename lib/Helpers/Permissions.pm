package Helpers::Permissions;

use Mojo::Base 'Mojolicious::Plugin';
use Data::Dumper;


has target => sub { };

sub register {
    my ($self, $app) = @_;

    $app->helper(perm => sub {
		     my $ctrl = shift;
		     $self->target($ctrl);
		     return $self;
		 });
}

sub update_info {
    my $self = shift;
    my $data = ref $_[0] ? $_[0] : { @_ };

    foreach my $info (qw/id username first_name last_name admin/) {
	if (exists $data->{$info}) {
	    $self->target->session('user_'.$info => $data->{$info});
	}
    }

    return;
}

sub remove_info {
    my $self = shift;

    map { delete $self->target->session->{$_} } qw(user_id user_username user_first_name user_last_name user_admin);
}

sub is_authd {
    my $self = shift;

    if ($self->target->session('user_id')) {
	return 1;
    }

    return 0;
}

sub is_admin {
    my $self = shift;

    return 0 unless defined $self->target->session('user_admin');

    if ($self->target->session('user_admin')) {
	return 1;
    }
    return 0;
}

1;
