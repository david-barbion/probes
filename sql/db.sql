drop table if exists graphs_options;
drop table if exists flot_options;
drop table if exists custom_graphs;
drop table if exists default_graphs;
drop table if exists probes_in_sets;
drop table if exists graphs;
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

-- Probes are the resulting tables from the probe set, the tables
-- columns depends on the version of PostgreSQL where the data comes
-- from. this tables allow to generate the probing script to run.
create table probes (
       id serial primary key,
       probe_name text not null,
       probe_type text not null,
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
       query text not null
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
       ('series-width', '0.5'),
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
create or replace function flot_time(timestamptz) returns bigint language 'sql' as
$$
SELECT ((extract(epoch FROM $1) + extract(timezone FROM $1))*1000)::bigint;
$$;


-- default probes
insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('cluster_hitratio', 'SQL', 'Cache hit/miss ratio on the cluster', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, round(sum(
  CASE 
    WHEN (blks_read::numeric*blks_hit::numeric)=0 then null
    ELSE 100-round((blks_read::numeric*100/(blks_read::numeric+blks_hit::numeric)),2)
  END
  )/count(*),2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname not in (''template0'',''template1'',''postgres'');', NULL, 'CREATE TABLE cluster_hitratio (
  datetime timestamptz,
  cache_hit_ratio float
);', 'sql/cluster_hitratio.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('databases_hitratio', 'SQL', 'Cache hit/miss ratio on databases', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  datname as database, round(
  CASE 
    WHEN (blks_read::numeric*blks_hit::numeric)=0 then null
    ELSE 100-round((blks_read::numeric*100/(blks_read::numeric+blks_hit::numeric)),2)
  END
  ,2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname not in (''template0'',''template1'',''postgres'');', NULL, 'CREATE TABLE databases_hitratio (
  datetime timestamptz,
  database text,
  cache_hit_ratio float
);', 'sql/databases_hitratio.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('tables_hitratio', 'SQL', 'Cache hit/miss ratio on tables, indexes and total', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
       schemaname as schema,
       relname as table,
       case when
           coalesce(heap_blks_read, 0) + coalesce(heap_blks_hit, 0) +
           coalesce(toast_blks_read, 0) + coalesce(toast_blks_hit, 0) = 0
       then 0
       else 100.0 * (coalesce(heap_blks_hit, 0) + coalesce(toast_blks_hit, 0)) /
             (coalesce(heap_blks_read, 0) + coalesce(heap_blks_hit, 0) +
              coalesce(toast_blks_read, 0) + coalesce(toast_blks_hit, 0))
       end as table_ratio,
       case when coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) +
                 coalesce(tidx_blks_read, 0) + coalesce(tidx_blks_hit, 0) = 0
       then 0
       else 100.0 * (coalesce(idx_blks_hit, 0) + coalesce(tidx_blks_hit, 0)) /
             (coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) +
              coalesce(tidx_blks_read, 0) + coalesce(tidx_blks_hit, 0))
       end as index_ratio,

       case when coalesce(heap_blks_read, 0) + coalesce(heap_blks_hit, 0) +
                 coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) +
                 coalesce(toast_blks_read, 0) + coalesce(toast_blks_hit, 0) +
                 coalesce(tidx_blks_read, 0) + coalesce(tidx_blks_hit, 0) = 0
       then 0
       else 100.0 * (coalesce(heap_blks_hit, 0) + coalesce(idx_blks_hit, 0) +
                     coalesce(toast_blks_hit, 0) + coalesce(tidx_blks_hit, 0)) /
             (coalesce(heap_blks_read, 0) + coalesce(heap_blks_hit, 0) +
              coalesce(idx_blks_read, 0) + coalesce(idx_blks_hit, 0) +
              coalesce(toast_blks_read, 0) + coalesce(toast_blks_hit, 0) +
              coalesce(tidx_blks_read, 0) + coalesce(tidx_blks_hit, 0))
       end as ratio
FROM pg_statio_user_tables;', NULL, 'CREATE TABLE tables_hitratio (
  datetime timestamptz,
  schema text,
  relation text,
  table_ratio float,
  index_ratio float,
  ratio float
);', 'sql/tables_hitratio.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('connections', 'SQL', 'Connections', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  COUNT(*) AS total, 
  coalesce(SUM((current_query NOT IN (''<IDLE>'',''<IDLE> in transaction''))::integer), 0) AS active, 
  coalesce(SUM(waiting::integer), 0) AS waiting,
  coalesce(SUM((current_query=''<IDLE> in transaction'')::integer), 0) AS idle_in_xact
FROM pg_stat_activity WHERE procpid <> pg_backend_pid();', NULL, 'CREATE TABLE connections (
  datetime timestamptz,
  total int,
  active int,
  waiting int,
  idle_in_xact int
);', 'sql/connections.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('read_write_ratio', 'SQL', 'Read / Write ratio on tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  relname as table,
  seq_tup_read,
  idx_tup_fetch,
  seq_tup_read + idx_tup_fetch AS n_tup_read,
  n_tup_ins, n_tup_upd, n_tup_del,
  100.0 * (seq_tup_read + idx_tup_fetch) / (n_tup_ins + n_tup_upd + n_tup_del + seq_tup_read + idx_tup_fetch) AS ratio
FROM pg_stat_user_tables
WHERE n_tup_ins + n_tup_upd + n_tup_del > 0;', NULL, 'CREATE TABLE read_write_ratio (
  datetime timestamptz,
  relation text,
  seq_tup_read bigint,
  idx_tup_fetch bigint,
  n_tup_read bigint,
  n_tup_ins bigint,
  n_tup_upd bigint,
  n_tup_del bigint,
  ratio float
);', 'sql/read_write_ratio.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('database_stats', 'SQL', 'Database statistics', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_stat_database;', NULL, 'CREATE TABLE database_stats (
  datetime timestamptz,
  datid bigint,
  datname text,
  numbackends  bigint,
  xact_commit bigint,
  xact_rollback bigint,
  blks_read bigint,
  blks_hit bigint,
  tup_returned bigint,
  tup_fetched bigint,
  tup_inserted bigint,
  tup_updated bigint,
  tup_deleted bigint,
  conflicts bigint,
  stats_reset timestamptz
);', 'sql/database_stats.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('bgwriter_stats', 'SQL', 'Background writer statistics', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_bgwriter;', NULL, 'CREATE TABLE bgwriter_stats (
  datetime timestamptz,
  checkpoints_timed bigint,
  checkpoints_req bigint,
  buffers_checkpoint bigint,
  buffers_clean bigint,
  maxwritten_clean bigint,
  buffers_backend bigint,
  buffers_backend_fsync bigint,
  buffers_alloc bigint,
  stats_reset timestamptz
)', 'sql/bgwriter_stats.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('user_tables', 'SQL', 'Statistics of user tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_user_tables;', NULL, 'CREATE TABLE user_tables (
  datetime timestamptz,
  relid bigint,
  schemaname text,
  relname text,
  seq_scan bigint,
  seq_tup_read bigint,
  idx_scan bigint,
  idx_tup_fetch bigint,
  n_tup_ins bigint,
  n_tup_upd bigint,
  n_tup_del bigint,
  n_tup_hot_upd bigint,
  n_live_tup bigint,
  n_dead_tup bigint,
  last_vacuum timestamptz,
  last_autovacuum timestamptz,
  last_analyze timestamptz,
  last_autoanalyze timestamptz,
  vacuum_count bigint,
  autovacuum_count bigint,
  analyze_count bigint,
  autoanalyze_count bigint
);', 'sql/user_tables.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('user_indexes', 'SQL', 'Statistics of user indexes', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_user_indexes;', NULL, 'CREATE TABLE user_indexes (
  datetime timestamptz,
  relid bigint,
  indexrelid bigint,
  schemaname text,
  relname text,
  indexrelname text,
  idx_scan bigint,
  idx_tup_read bigint,
  idx_tup_fetch bigint
);', 'sql/user_indexes.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('io_user_tables', 'SQL', 'I/O Statistics on all tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_statio_all_tables;', NULL, 'CREATE TABLE io_user_tables (
  datetime timestamptz,
  relid bigint,
  schemaname text,
  relname text,
  heap_blks_read bigint,
  heap_blks_hit bigint,
  idx_blks_read bigint,
  idx_blks_hit bigint,
  toast_blks_read bigint,
  toast_blks_hit bigint,
  tidx_blks_read bigint,
  tidx_blks_hit bigint
);', 'sql/io_user_tables.csv', true);

insert into probes (probe_name, probe_type, description, version, command, preload_command, target_ddl_query, source_path, enabled) values ('io_user_indexes', 'SQL', 'I/O Statistics on all indexes', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_statio_all_indexes;', NULL, 'CREATE TABLE io_user_indexes (
  datetime timestamptz,
  relid bigint,
  indexrelid bigint,
  schemaname text,
  relname text,
  indexrelname text,
  idx_blks_read bigint,
  idx_blks_hit bigint
);', 'sql/io_user_indexes.csv', true);
