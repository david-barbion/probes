package Probe::Users;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;
use Digest::SHA qw(sha256_hex);

sub login {
    my $self = shift;

    # Do not go through the login process if the user is already in
    if ($self->perm->is_authd) {
	return $self->redirect_to('site_home');
    }

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# Check input values
	my $e = 0;
	if ($form_data->{username} =~ m/^\s*$/) {
	    $self->msg->error("Empty username");
	    $e = 1;
	}

	if ($form_data->{password} =~ m/^\s*$/) {
	    $self->msg->error("Empty password");
	    $e = 1;
	}

	return $self->render() if ($e);

	my $dbh = $self->database;
	my $sth = $dbh->prepare(qq{SELECT id, first_name, last_name, is_admin FROM users WHERE username = ? AND password = ?});
	$sth->execute($form_data->{username}, sha256_hex($form_data->{password}));
	my ($id, $f, $l, $a) = $sth->fetchrow();
	$sth->finish;
	$dbh->commit;
	$dbh->disconnect;

	if (defined $id) {
	    $self->perm->update_info(id => $id,
				     username => $form_data->{username},
				     first_name => $f,
				     last_name => $l,
				     admin => $a);

	    return $self->redirect_to('site_home');
	} else {
	    $self->msg->error("Authentication failed");
	}
    }

    $self->render();
}

sub logout {
    my $self = shift;

    if ($self->perm->is_authd) {
	$self->msg->info("You have logged out.");
    }

    $self->perm->remove_info;

    $self->redirect_to('site_home');
}

sub register {
    my $self = shift;

    # Do not go through the registration process if the user is already in
    if ($self->perm->is_authd) {
	return $self->redirect_to('site_home');
    }

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# Check input values
	my $e = 0;
	if ($form_data->{username} =~ m/^\s*$/) {
	    $self->msg->error("Empty username");
	    $e = 1;
	}

	if ($form_data->{password} =~ m/^\s*$/) {
	    $self->msg->error("Empty password");
	    $e = 1;
	} elsif ($form_data->{confirm_password} ne $form_data->{password}) {
	    $self->msg->error("Passwords do not match");
	    $e = 1;
	}

	if ($form_data->{email} =~ m/^\s*$/) {
	    $self->msg->error("Empty E-mail");
	    $e = 1;
	} elsif ($form_data->{email} !~ m/^[\w\.\+\-]+@[\w\.\+\-]+\.[\w\-]+$/i) {
	    $self->msg->error("Bad E-mail format");
	    $e = 1;
	}

	return $self->render() if ($e);

	# Check if the user already exists
	my $dbh = $self->database;
	my $sth = $dbh->prepare(qq{SELECT username, email FROM users WHERE username = ? OR email = ?});
	$sth->execute($form_data->{username}, $form_data->{email});
	my ($u, $m) = $sth->fetchrow();
	$sth->finish;

	if (defined $u or defined $m) {
	    $self->msg->error("An account with this username or e-mail already exists");
	    $dbh->commit;
	    $dbh->disconnect;
	    return $self->render();
	}

	# Add the user
	$sth = $dbh->prepare(qq{INSERT INTO users (username, password, email, first_name, last_name)
VALUES (?, ?, ?, ?, ?) RETURNING id, is_admin});
	if (! $sth->execute($form_data->{username},
			    sha256_hex($form_data->{password}),
			    $form_data->{email},
			    $form_data->{first_name} ||= undef,
			    $form_data->{last_name} ||= undef)) {
	    $sth->finish;
	    $dbh->rollback;
	    $dbh->disconnect;
	    $self->msg->error("Registration failed. Please contact the site administrators.");
	    return $self->render();
	}

	# Get the new id and add it to the session, so that the new user is logged in directly
	my ($id, $a) = $sth->fetchrow();
	$sth->finish;
	$dbh->commit;
	$dbh->disconnect;

	$self->perm->update_info(id => $id,
				 username => $form_data->{username},
				 first_name => $form_data->{first_name} ||= undef,
				 last_name => $form_data->{last_name} ||= undef,
				 admin => $a);

	# Redirect to the home page
	return $self->redirect_to('site_home');
    }

    # Display the form
    $self->render();
}

sub profile {
    my $self = shift;

    my $id = $self->session('user_id');
    my $dbh = $self->database;

    # Make the profile pane active
    $self->stash(profile_pane => 'active',
		 account_pane => undef,
		 password_pane => undef);

    # Get the information of the page
    my $sth = $dbh->prepare(qq{SELECT username, email, first_name, last_name, upload_count
FROM users
WHERE id = ?});
    if (! $sth->execute($id)) {
	$sth->finish;
	$dbh->rollback;
	$dbh->disconnect;
	$self->msg->error("Account not found");
	return $self->redirect_to('site_home');
    }

    my ($u, $e, $f, $l, $c) = $sth->fetchrow();
    $sth->finish;

    $self->stash(username => $u,
		 email => $e,
		 first_name => $f,
		 last_name => $l,
		 uploads => $c);

    $dbh->commit;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# There are two different forms, one for the account
	# information, one to change the password
	if ($form_data->{save_account}) {

	    # Check input values
	    my $e = 0;
	    if ($form_data->{username} =~ m/^\s*$/) {
		$self->msg->error("Empty username");
		$e = 1;
	    }

	    if ($form_data->{email} =~ m/^\s*$/) {
		$self->msg->error("Empty E-mail");
		$e = 1;
	    } elsif ($form_data->{email} !~ m/^[\w\.\+\-]+@[\w\.\+\-]+\.[\w\-]+$/i) {
		$self->msg->error("Bad E-mail format");
		$e = 1;
	    }

	    # Make the account pane active
	    $self->stash(profile_pane => undef,
			 account_pane => 'active',
			 password_pane => undef);

	    return $self->render() if ($e);

	    my $sth = $dbh->prepare(qq{UPDATE users SET username = ?, email = ?, first_name = ?, last_name =?
WHERE id = ?});
	    if (! $sth->execute($form_data->{username},
				$form_data->{email},
				$form_data->{first_name} ||= undef,
				$form_data->{last_name} ||= undef,
				$id)) {
		$self->msg->error("Update failed.");
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		return $self->render();
	    }

	    $sth->finish;
	    $dbh->commit;
	    $dbh->disconnect;

	    # Update the session with the new data
	    $self->session('user_username' => $form_data->{username});
	    $self->session('user_first_name' => $form_data->{first_name} ||= undef);
	    $self->session('user_last_name' => $form_data->{last_name} ||= undef);

	    $self->msg->info("Information updated.");

	    return $self->render();
	}

	# Process password update form
	if ($form_data->{save_password}) {
	    # Check input values
	    my $e = 0;
	    if ($form_data->{current_password} =~ m/^\s*$/) {
		$self->msg->error("Empty current password");
		$e = 1;
	    }

	    if ($form_data->{password} =~ m/^\s*$/) {
		$self->msg->error("Empty new password");
		$e = 1;
	    } elsif ($form_data->{confirm_password} ne $form_data->{password}) {
		$self->msg->error("Passwords do not match");
		$e = 1;
	    }

	    # Make the password pane active
	    $self->stash(profile_pane => undef,
			 account_pane => undef,
			 password_pane => 'active');

	    return $self->render() if ($e);

	    # First check if the current password given is correct
	    my $sth = $dbh->prepare(qq{SELECT 1 FROM users WHERE id = ? AND password = ?});
	    if (! $sth->execute($id, sha256_hex($form_data->{current_password}))) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not validate current password.");
		return $self->render;
	    }

	    my ($res) = $sth->fetchrow();
	    $sth->finish;

	    if (! defined $res) {
		$self->msg->error("Invalid current password.");
		$dbh->commit;
		$dbh->disconnect;
		return $self->render;
	    }

	    # Update the password
	    $sth = $dbh->prepare(qq{UPDATE users SET password = ? WHERE id = ?});
	    if (! $sth->execute(sha256_hex($form_data->{password}), $id)) {
		$sth->finish;
		$dbh->rollback;
		$dbh->disconnect;
		$self->msg->error("Could not update the password.");
		return $self->render;
	    }

	    $self->msg->info("Password updated.");

	    $sth->finish;
	    $dbh->commit;
	    $dbh->disconnect;
	    return $self->render;

	}
    }

    $dbh->disconnect;

    $self->render();
}

sub check {
    my $self = shift;

    # Make the dispatch continue when the user id is found in the session
    if($self->perm->is_authd) {
	return 1;
    }

    # Display the login form only if we are not on the home page
    if ($self->current_route eq 'site_home') {
	# Display the welcome page, the regular home page is for logged in people
	return $self->render(template => 'site/welcome');
    } else {
	$self->redirect_to('users_login');
        return 0;
    }
}

1;
