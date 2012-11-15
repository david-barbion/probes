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

-- Path in the archive must be unique in order to select the proper
-- probe, thus table creation query, when loading the data
alter table probes add unique (source_path);

-- Allow to create probes for any versions
alter table probes alter min_version drop not null;

