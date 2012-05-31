drop table if exists graphs_options;
drop table if exists flot_options;
drop table if exists custom_graphs;
drop table if exists default_graphs;
drop table if exists probes_in_sets;
drop table if exists graphs;
drop table if exists probe_types;
drop table if exists probes;
drop table if exists probe_sets;

-- A probe set is a loaded archive with the data in the corresponding
-- schema
create table probe_sets (
       id serial primary key,
       set_name text unique not null,
       nsp_name text unique not null,
       description text not null,
       upload_time timestamptz not null
);

create table probe_types (
       id serial primary key,
       probe_type text unique not null,
       description text not null,
       runner_key text unique not null -- internal name for run implementation inside probe_runner.pl
);

insert into probe_types (id, probe_type, description, runner_key) values (1, 'SQL', 'Run a SQL query with psql', 'sql');
insert into probe_types (id, probe_type, description, runner_key) values (2, 'sysstat', 'Get the system statistics gathered by sysstat', 'sar');
insert into probe_types (id, probe_type, description, runner_key) values (3, 'Command', 'Run a system command', 'command');
insert into probe_types (id, probe_type, description, runner_key) values (4, 'Fork Command', 'Run a non returning system command within another process', 'fork');

select pg_catalog.setval('probe_types_id_seq', 4, true);

-- Probes are the resulting tables from the probe set, the tables
-- columns depends on the version of PostgreSQL where the data comes
-- from. this tables allow to generate the probing script to run.
create table probes (
       id serial primary key,
       probe_name text not null,
       probe_type integer not null references probe_types(id),
       description text,
       version text not null,
       command text, -- command/query to get the data from PostgreSQL, eg null for sysstat
       preload_command text, -- command to transform whatever file the source path found to CSV, null if already CSV
       target_ddl_query text not null, -- query to create the target table
       source_path text not null, -- path inside the result archive to access the result file, if it is a directory load all files within
       enabled bool not null -- whether the probe will be available for script generation and to the result loader
);

-- N to N link between probes and sets
create table probes_in_sets (
       id_set integer not null references probe_sets(id),
       id_probe integer not null references probes(id)
);

-- saved queries to generate graph on probe datas
create table graphs (
       id serial primary key,
       graph_name text not null,
       description text,
       query text not null,
       filter_query text
);

-- saved graphs for use with any probe
create table default_graphs (
       id_graph integer not null references graphs(id),
       id_probe integer not null references probes(id)
);

-- list of all graphs selected for a probe set
create table custom_graphs (
       id_graph integer not null references graphs(id),
       id_set integer not null references probe_sets(id)
);

-- display options for graphs
create table flot_options (
       id serial primary key,
       option_name text unique not null, -- input name
       default_value text not null
);

-- default options
insert into flot_options (option_name, default_value) values
       ('stacked', 'off'),
       ('legend-cols', '1'),
       ('series-width', '1'),
       ('show-legend', 'off'),
       ('graph-type', 'lines'),
       ('filled', 'off');

-- link options to graphs with values
create table graphs_options (
       id_graph integer not null references graphs(id),
       id_option integer not null references flot_options(id),
       option_value text not null
);

-- function to help get the proper timestamp usable by flot: offset
-- from epoch in millisecond in the local time
create or replace function js_time(timestamptz) returns bigint language 'sql' as
$$
SELECT ((extract(epoch FROM $1) + extract(timezone FROM $1))*1000)::bigint;
$$;

