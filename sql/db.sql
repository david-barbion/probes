drop table if exists graphs_options;
drop table if exists plot_options;
drop table if exists report_contents;
drop table if exists reports;
drop table if exists script_probes;
drop table if exists scripts;
drop table if exists probe_graphs;
drop table if exists graphs;
drop table if exists probes_in_sets;
drop table if exists probes;
drop table if exists probe_types;
drop table if exists results;
drop table if exists users;


create table users (
       id serial primary key,
       username text unique not null,
       password text not null,
       email text not null,
       first_name text,
       last_name text,
       id_group integer references users (id),
       is_admin bool not null default false,
       upload_count integer not null default 0
);

create index users_id_group_idx on users (id_group);

insert into users values (1, 'admin', 'c1c224b03cd9bc7b6a86d77f5dace40191766c485cd55dc48caf9ac873335d6f', 'root@example.com', NULL, NULL, NULL, true, 0);

select pg_catalog.setval('users_id_seq', 1, true);

-- A result set is a loaded archive with the data in the corresponding
-- schema
create table results (
       id serial primary key,
       set_name text unique not null,
       description text not null,
       chain_id integer not null default 0,
       upload_time timestamptz not null,
       id_owner integer references users (id)
);

create index results_id_owner_idx on results (id_owner);

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
       probe_type integer not null references probe_types (id),
       description text,
       min_version text not null,
       max_version text,
       command text, -- command/query to get the data from PostgreSQL, eg null for sysstat
       preload_command text, -- command to transform whatever file the source path found to CSV, null if already CSV
       target_ddl_query text not null, -- query to create the target table
       source_path text not null, -- path inside the result archive to access the result file, if it is a directory load all files within
       enabled bool not null, -- whether the probe will be available for script generation and to the result loader
       id_owner integer references users (id)
);

create index probes_probe_type_idx on probes (probe_type);
create index probes_id_owner_idx on probes (id_owner);

-- N to N link between probes and sets
create table probes_in_sets (
       id_result integer not null references results (id),
       id_probe integer not null references probes (id),
       primary key (id_result, id_probe)
);

create index probes_in_sets_id_probe_idx on probes_in_sets (id_probe);

-- saved queries to generate graph on probe datas
create table graphs (
       id serial primary key,
       graph_name text not null,
       description text,
       query text not null,
       yquery text,
       filter_query text,
       id_owner integer references users (id)
);

create index graphs_id_owner_idx on graphs (id_owner);

-- saved graphs for use with any probe
create table probe_graphs (
       id_graph integer not null references graphs(id),
       id_probe integer not null references probes(id),
       primary key (id_graph, id_probe)
);

create index probe_graphs_id_probe_idx on probe_graphs (id_probe);

-- custom scripts
create table scripts (
       id serial primary key,
       script_name text not null,
       description text,
       id_owner integer references users (id)
);

create index scripts_id_owner_idx on scripts (id_owner);

create table script_probes (
       id_script integer not null references scripts (id),
       id_probe integer not null references probes (id),
       primary key (id_script, id_probe)
);

create index script_probes_id_probe_idx on script_probes (id_probe);


-- reports
create table reports (
       id serial primary key,
       report_name text not null,
       description text,
       id_owner integer references users(id)
);

create index reports_id_owner_idx on reports (id_owner);

create table report_contents (
       id_report integer not null references reports(id),
       id_result integer not null references results(id),
       id_graph integer not null references graphs(id),
       primary key (id_report, id_result, id_graph)
);

create index report_contents_id_result_idx on report_contents (id_result);
create index report_contents_id_graph_idx on report_contents (id_graph);

-- display options for graphs
create table plot_options (
       id serial primary key,
       option_name text unique not null, -- input name
       default_value text not null
);

-- default options
insert into plot_options (option_name, default_value) values
       ('stacked', 'off'),
       ('legend-cols', '1'),
       ('series-width', '1'),
       ('show-legend', 'off'),
       ('graph-type', 'lines'),
       ('filled', 'off');

-- link options to graphs with values
create table graphs_options (
       id_graph integer not null references graphs(id),
       id_option integer not null references plot_options(id),
       option_value text not null,
       primary key (id_graph, id_option)
);

create index graphs_options_id_option_idx on graphs_options (id_option);

-- function to help get the proper timestamp usable by flot: offset
-- from epoch in millisecond in the local time
create or replace function js_time(timestamptz) returns bigint language 'sql' as
$$
SELECT ((extract(epoch FROM $1) + extract(timezone FROM $1))*1000)::bigint;
$$;

