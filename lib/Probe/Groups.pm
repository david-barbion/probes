package Probe::Groups;
use Mojo::Base 'Mojolicious::Controller';

use Data::Dumper;

sub list {
    my $self = shift;

    my $dbh = $self->database;
    my $sth = $dbh->prepare(qq{SELECT g.id, g.group_name, g.description, array_agg(u.id ORDER BY u.username), array_agg(u.username ORDER BY u.username)
FROM groups g
  LEFT JOIN group_members m ON (g.id = m.id_group)
  LEFT JOIN users u ON (u.id = m.id_user)
GROUP BY 1, 2, 3});
    $sth->execute;

    my $groups = [ ];
    while (my ($i, $n, $d, $u, $m) = $sth->fetchrow) {
	# Merge the two aggregated arrays into a hash { uid => username }
	# to allow creating links to the user edit page for each member
	my $members = { };
	for (my $j = 0; $j < @{$u}; $j++) {
	    last if ! defined $u->[$j];
	    $members->{$u->[$j]} = $m->[$j];
	}
	push @{$groups}, { id => $i, name => $n, desc => $d, members => $members };
    }
    $sth->finish;

    $self->stash(groups => $groups);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub add {
    my $self = shift;

    my $method = $self->req->method;
    my $dbh = $self->database;

    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            return $self->redirect_to('groups_list');
        }

	my $e = 0;

	# Mandatory fields
	if ($form_data->{name} =~ m!^\s*$!s) {
            $self->msg->error("Empty group name");
            $e = 1;
        }

	unless ($e) {
	    my $rb = 0;

	    # Add the new group
	    my $sth = $dbh->prepare(qq{INSERT INTO groups (group_name, description)
VALUES (?, ?) RETURNING id});
	    $rb = 1 unless $sth->execute($form_data->{name},
					 $form_data->{desc} ||= undef);
	    my ($gid) = $sth->fetchrow;
	    $sth->finish;

	    # XXX: check if there is a unique constraint violation on group_name -> message

	    if (exists $form_data->{members} and defined $gid) {
		my @u = (ref $form_data->{members} eq '') ? ($form_data->{members}) : @{$form_data->{members}};
		$sth = $dbh->prepare(qq{INSERT INTO group_members (id_group, id_user) VALUES (?, ?)});
		foreach my $uid (@u) {
		    if (! defined $sth->execute($gid, $uid)) {
			$rb = 1;
			last;
		    }
		}
		$sth->finish;
	    }

	    if ($rb) {
		$self->msg->error("An error occured while creating the group");
		$dbh->rollback;
	    } else {
		$self->msg->info("Group created");
		$dbh->commit;
	    }

	    $dbh->disconnect;
	    return $self->redirect_to('groups_list');
	}
    }

    # Get the list of users for the select member form entry
    my $sth = $dbh->prepare(qq{SELECT id, username, first_name, last_name FROM users ORDER BY username});
    $sth->execute;
    my $users = [ ];
    while (my ($i, $u, $fn, $ln) = $sth->fetchrow) {
	my $name = '';
	$name = '(' . join(' ', $fn, $ln) . ')' unless (!defined $fn and !defined $ln);
	push @{$users}, [ $u . ' ' . $name => $i ];
    }
    $sth->finish;

    $self->stash(users => $users);

    $self->render;
}

sub edit {
    my $self = shift;

    my $id = $self->param('id');
    my $e = 0;

    my $dbh = $self->database;

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
	    $dbh->disconnect;
            return $self->redirect_to('groups_list');
        }

	# Mandatory fields
	if ($form_data->{name} =~ m!^\s*$!s) {
            $self->msg->error("Empty group name");
            $e = 1;
        }

	unless ($e) {
	    my $rb = 0;

	    # Update
	    my $sth = $dbh->prepare(qq{UPDATE groups SET group_name = ?, description = ? WHERE id = ?});
	    $rb = 1 unless $sth->execute($form_data->{name},
					 $form_data->{desc},
					 $id);
	    $sth->finish;

	    # purge membership to reinsert modifications
	    $sth = $dbh->prepare(qq{DELETE FROM group_members WHERE id_group = ?});
	    $rb = 1 unless $sth->execute($id);
	    $sth->finish;

	    if (exists $form_data->{members}) {
		my @u = (ref $form_data->{members} eq '') ? ($form_data->{members}) : @{$form_data->{members}};
		$sth = $dbh->prepare(qq{INSERT INTO group_members (id_group, id_user) VALUES (?, ?)});
		foreach my $uid (@u) {
		    if (! defined $sth->execute($id, $uid)) {
			$rb = 1;
			last;
		    }
		}
		$sth->finish;
	    }

	    if ($rb) {
		$self->msg->error("An error occured while updating the group");
		$dbh->rollback;
	    } else {
		$self->msg->info("Group updated");
		$dbh->commit;
	    }

	    $dbh->disconnect;
	    return $self->redirect_to('groups_list');
	}
    }

    # get the info on the group to prepare the form
    my $sth = $dbh->prepare(qq{SELECT g.group_name, g.description, array_agg(u.id)
FROM groups g
  LEFT JOIN group_members m ON (g.id = m.id_group)
  LEFT JOIN users u ON (u.id = m.id_user)
WHERE g.id = ?
GROUP BY 1, 2});
    $sth->execute($id);
    my ($n, $d, $m) = $sth->fetchrow;
    $sth->finish;

    # check if input id exists
    if (! defined $n) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    # Prefill the form unless there was some error in the form validation
    unless ($e) {
	$self->param('name', $n);
	$self->param('desc', $d);
	$self->param('members', $m);
    }

    # Get the list of users for the select member form entry
    $sth = $dbh->prepare(qq{SELECT id, username, first_name, last_name FROM users ORDER BY username});
    $sth->execute;
    my $users = [ ];
    while (my ($i, $u, $fn, $ln) = $sth->fetchrow) {
	my $name = '';
	$name = '(' . join(' ', $fn, $ln) . ')' unless (!defined $fn and !defined $ln);
	push @{$users}, [ $u . ' ' . $name => $i ];
    }
    $sth->finish;

    $self->stash(users => $users);

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

sub remove {
    my $self = shift;

    my $id = $self->param('id');

    my $method = $self->req->method;
    if ($method =~ m/^POST$/i) {
        # process the input data
        my $form_data = $self->req->params->to_hash;

        # Redirect if cancel button has been pressed
        if (exists $form_data->{cancel}) {
            return $self->redirect_to('groups_list');
        }

	my $rb = 0;

	# purge membership
	my $dbh = $self->database;
	my $sth = $dbh->prepare(qq{DELETE FROM group_members WHERE id_group = ?});
	$rb = 1 unless $sth->execute($id);
	$sth->finish;


	$sth = $dbh->prepare(qq{DELETE FROM groups WHERE id = ?});
	$rb = 1 unless $sth->execute($id);
	$sth->finish;

	if ($rb) {
	    $self->msg->error("An error occured while removing the group");
	    $dbh->rollback;
	} else {
	    $self->msg->info("Group removed");
	    $dbh->commit;
	}

	$dbh->disconnect;
	return $self->redirect_to('groups_list');
    }

    my $dbh = $self->database;
    # get the info on the group to prepare the form
    my $sth = $dbh->prepare(qq{SELECT g.group_name, g.description, string_agg(u.username, ', ' ORDER BY u.username)
FROM groups g
  LEFT JOIN group_members m ON (g.id = m.id_group)
  LEFT JOIN users u ON (u.id = m.id_user)
WHERE g.id = ?
GROUP BY 1, 2});
    $sth->execute($id);
    my ($n, $d, $m) = $sth->fetchrow;
    $sth->finish;

    # check if input id exists
    if (! defined $n) {
	$dbh->commit;
	$dbh->disconnect;
	return $self->render_not_found;
    }

    $self->stash(group => { name => $n, desc => $d, members => $m });

    $dbh->commit;
    $dbh->disconnect;

    $self->render;
}

1;
