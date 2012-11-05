-- Changes from init (0.99.0) to 0.99.1

-- Replace the self referencing id_group column from users
alter table users drop constraint users_id_group_fkey;

alter table users drop column id_group;

-- Group table or self-reference ??
create table groups (
       id serial primary key,
       group_name text unique not null,
       description text
);

-- Use a link table to allow users into different groups.
create table group_members (
       id_group integer references groups (id),
       id_user integer references users (id),
       primary key (id_group, id_user)
);

