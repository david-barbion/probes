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

	    my $target = $self->session('goback') || 'site_home';
	    delete $self->session->{goback};
	    return $self->redirect_to($target);
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

sub check_auth {
    my $self = shift;

    # Make the dispatch continue when the user id is found in the session
    if($self->perm->is_authd) {
	return 1;
    }

    # Remember the route to go back to the page that triggered the auth form
    $self->session(goback => $self->current_route);
    $self->redirect_to('users_login');

    return 0;

}

sub check_admin {
    my $self = shift;

    # Make the dispatch continue only if the user has admin privileges
    if($self->perm->is_admin) {
	return 1;
    }

    # When the user has no privileges, do not redirect, send 401 unauthorized instead
    $self->render('unauthorized', status => 401);

    return 0;
}

sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT id, username, email, first_name, last_name, is_admin, upload_count
FROM users
ORDER BY username});
    $sth->execute;
    my $users = [ ];
    while (my ($i, $u, $e, $fn, $ln, $a, $c) = $sth->fetchrow) {
	push @{$users}, { id => $i, name => $u, email => $e, fname => $fn,
			  lname => $ln, admin => $a, uploads => $c };
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(users => $users);

    $self->render;
}

sub add {
    my $self = shift;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# Action depends on the name of the button pressed
	if (exists $form_data->{save}) {
	    # Error processing
	    my $e = 0;

	    if ($form_data->{username} eq '') {
		$self->msg->error("Empty username");
		$e = 1;
	    }
	    if ($form_data->{email} eq '') {
		$self->msg->error("Empty E-mail address");
		$e = 1;
	    }
	    if ($form_data->{passwd} eq '') {
		$self->msg->error("Empty password");
		$e = 1;
	    }

	    unless ($e) {
		my $dbh = $self->database;
		my $rb = 0;

		my $sth = $dbh->prepare(qq{INSERT INTO users (username, password, email, first_name, last_name, is_admin) VALUES (?, ?, ?, ?, ?, ?)});
$rb = 1 unless defined $sth->execute($form_data->{username},
				     sha256_hex($form_data->{passwd}),
				     $form_data->{email},
				     $form_data->{fname} ||= undef,
				     $form_data->{lname} ||= undef,
				     $form_data->{admin} ||= 0);

		$sth->finish;

		if ($rb) {
		    if ($dbh->state eq '23505') { # Unique violation contraint on username
			$self->msg->error("Username already exists");
		    } else {
			$self->msg->error("An error occured while saving. Action has been cancelled");
		    }
		    $dbh->rollback;
		    $dbh->disconnect;
		} else {
		    $self->msg->info("Account creation successful");
		    $dbh->commit;
		    $dbh->disconnect;
		    return $self->redirect_to('users_list');
		}
	    }
	} else {
	    # Cancel button pressed
	    return $self->redirect_to('users_list');
	}
    }

    $self->render;
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');
    my $e = 0;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

	# Action depends on the name of the button pressed
	if (exists $form_data->{save}) {
	    # Error processing
	    if ($form_data->{username} eq '') {
		$self->msg->error("Empty username");
		$e = 1;
	    }
	    if ($form_data->{email} eq '') {
		$self->msg->error("Empty E-mail address");
		$e = 1;
	    }

	    unless ($e) {
		my $dbh = $self->database;
		my $sth;
		my $rb = 0;
		if ($form_data->{passwd} eq '') {
		    $sth = $dbh->prepare(qq{UPDATE users SET username = ?, email = ?, first_name = ?,
  last_name = ?, is_admin = ?
WHERE id = ?});
		    $rb = 1 unless defined $sth->execute($form_data->{username},
							 $form_data->{email},
							 $form_data->{fname} ||= undef,
							 $form_data->{lname} ||= undef,
							 $form_data->{admin} ||= 0,
							 $id);
		    $sth->finish;
		} else {
		    # Update the password too
		    $sth = $dbh->prepare(qq{UPDATE users SET username = ?, password = ?, email = ?,
  first_name = ?, last_name = ?, is_admin = ?
WHERE id = ?});
		    $rb = 1 unless defined $sth->execute($form_data->{username},
							 sha256_hex($form_data->{passwd}),
							 $form_data->{email},
							 $form_data->{fname} ||= undef,
							 $form_data->{lname} ||= undef,
							 $form_data->{admin} ||= 0,
							 $id);
		    $sth->finish;
		}

		if ($rb) {
		    if ($dbh->state eq '23505') { # Unique violation contraint on username
			$self->msg->error("Username already exists");
		    } else {
			$self->msg->error("An error occured while saving. Action has been cancelled");
		    }
		    $dbh->rollback;
		    $dbh->disconnect;
		} else {
		    $self->msg->info("Account update successful");
		    $dbh->commit;
		    $dbh->disconnect;
		    return $self->redirect_to('users_list');
		}
	    }
	} else {
	    return $self->redirect_to('users_list');
	}
    }

    my $dbh = $self->database;
    # Get the account data
    my $sth = $dbh->prepare(qq{SELECT username, email, first_name, last_name, is_admin, upload_count
FROM users WHERE id = ?});
    $sth->execute($id);
    my ($u, $m, $fn, $ln, $a, $c) = $sth->fetchrow;
    $sth->finish;
    $dbh->commit;
    $dbh->disconnect;

    # Check if the user exists
    if (!defined $u) {
	return $self->render_not_found;
    }

    # Set the state of the admin checkbox, without overwriting the
    # submitted data when a save error occurs
    $self->param('admin', 'on') if ($a && !$e);

    $self->stash(user => { name => $u,
			   email => $m,
			   fname => $fn,
			   lname => $ln,
			   uploads => $c });

    $self->render;
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');

    my  $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
	# process the input data
	my $form_data = $self->req->params->to_hash;

	# Redirect if cancel button has been pressed
	if (exists $form_data->{remove}) {

	    my $e = 0;
	    if (exists $form_data->{data}) {
		if ($form_data->{data} eq 'reassign' && $form_data->{to_user} eq '') {
		    $self->msg->error("Undefined target user for ownership transfer");
		    $e = 1;
		}
	    } else {
		$self->msg->error("Action for data undefined");
		$e = 1;
	    }

	    unless ($e) {
		my $dbh = $self->database;
		my $sth;
		my $rb = 0;

		if ($form_data->{data} eq 'reassign') {
		    # Update everything using the provided id
		    foreach my $t (qw/graphs probes reports results scripts/) {
			$sth = $dbh->prepare(qq{UPDATE $t SET id_owner = ? WHERE id_owner = ?});
			unless (defined $sth->execute($form_data->{to_user},
						      $id)) {
			    $rb = 1;
			    last;
			}
		    }

		    $sth->finish;
		} else {
		    # Remove everything owned by the user
		    # Reports
		    $sth = $dbh->prepare(qq{DELETE FROM report_contents USING reports
WHERE id_report = reports.id AND reports.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM reports WHERE id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    # Graphs
		    $sth = $dbh->prepare(qq{DELETE FROM graphs_options USING graphs
WHERE id_graph = graphs.id AND graphs.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM report_contents USING graphs
WHERE id_graph = graphs.id AND graphs.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM probe_graphs USING graphs
WHERE id_graph = graphs.id AND graphs.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM graphs WHERE id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    # Results
		    $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets USING results
WHERE id_result = results.id AND results.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM report_contents USING results
WHERE id_result = results.id AND results.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM results WHERE id_owner = ? RETURNING id});
		    $rb = 1 unless defined $sth->execute($id);

		    while (my ($i) = $sth->fetchrow) {
			$rb = 1 unless $dbh->do(qq{DROP SCHEMA data_$i CASCADE});
		    }

		    $sth->finish;

		    # Scripts
		    $sth = $dbh->prepare(qq{DELETE FROM script_probes USING scripts
WHERE id_script = scripts.id AND scripts.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM scripts WHERE id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    # Probes
		    $sth = $dbh->prepare(qq{DELETE FROM probes_in_sets USING probes
WHERE id_probe = probes.id AND probes.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM probe_graphs USING probes
WHERE id_probe = probes.id AND probes.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM script_probes USING probes
WHERE id_probe = probes.id AND probes.id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;

		    $sth = $dbh->prepare(qq{DELETE FROM probes WHERE id_owner = ?});
		    $rb = 1 unless defined $sth->execute($id);
		    $sth->finish;
		}

		# Remove the user
		$sth = $dbh->prepare(qq{DELETE FROM users WHERE id = ?});
		$rb = 1 unless defined $sth->execute($id);
		$sth->finish;

		if ($rb) {
		    $self->msg->error("An error occured while saving. Action has been cancelled");
		    $dbh->rollback;
		    $dbh->disconnect;
		} else {
		    $self->msg->info("Account removed");
		    $dbh->commit;
		    $dbh->disconnect;
		    return $self->redirect_to('users_list');
		}
	    }
	} else {
	    # Cancel button
	    return $self->redirect_to('users_list');
	}
    }

    my $dbh = $self->database;
    # Get the account data
    my $sth = $dbh->prepare(qq{SELECT username, email, first_name, last_name, is_admin
FROM users WHERE id = ?});
    $sth->execute($id);
    my ($u, $m, $fn, $ln, $a) = $sth->fetchrow;
    $sth->finish;

    # Check if the user exists
    if (!defined $u) {
	return $self->render_not_found;
    }

    # Get the list of account for reassign ownership
    $sth = $dbh->prepare(qq{SELECT id, username, first_name, last_name FROM users
WHERE id <> ?});
    $sth->execute($id);

    my $users = [ '' ];
    while (my ($i, $n, $f, $l) = $sth->fetchrow) {
	$f = '' if (! defined $f);
	$l = '' if (! defined $l);
	push @{$users}, [ qq{$n ($f $n)} => $i ];
    }
    $sth->finish;

    $dbh->commit;
    $dbh->disconnect;

    $self->stash(users => $users);
    $self->stash(user => { name => $u,
			   email => $m,
			   fname => $fn,
			   lname => $ln,
			   admin => $a});

    $self->render;
}


1;
