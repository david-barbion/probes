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
-- from. this tables allow to generate to probing script to run.
create table probes (
       id serial primary key,
       probe_name text not null,
       description text,
       version text not null,
       probe_query text not null,
       ddl_query text
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
       ('graph-type', 'points'),
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
insert into probes (probe_name, description, version, probe_query) values ('cluster_hitratio', 'Cache hit/miss ratio on the cluster', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, round(sum(
  CASE 
    WHEN (blks_read::numeric*blks_hit::numeric)=0 then null
    ELSE 100-round((blks_read::numeric*100/(blks_read::numeric+blks_hit::numeric)),2)
  END
  )/count(*),2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname not in (''template0'',''template1'',''postgres'');');

insert into probes (probe_name, description, version, probe_query) values ('databases_hitratio', 'Cache hit/miss ratio on databases', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  datname as database, round(
  CASE 
    WHEN (blks_read::numeric*blks_hit::numeric)=0 then null
    ELSE 100-round((blks_read::numeric*100/(blks_read::numeric+blks_hit::numeric)),2)
  END
  ,2) as cache_hit_ratio
FROM pg_stat_database
WHERE datname not in (''template0'',''template1'',''postgres'');');

insert into probes (probe_name, description, version, probe_query) values ('tables_hitratio', 'Cache hit/miss ratio on tables, indexes and total', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
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
FROM pg_statio_user_tables;');

insert into probes (probe_name, description, version, probe_query) values ('connections', 'Connections', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  COUNT(*) AS total, 
  coalesce(SUM((current_query NOT IN (''<IDLE>'',''<IDLE> in transaction''))::integer), 0) AS active, 
  coalesce(SUM(waiting::integer), 0) AS waiting,
  coalesce(SUM((current_query=''<IDLE> in transaction'')::integer), 0) AS idle_in_xact
FROM pg_stat_activity WHERE procpid <> pg_backend_pid();');

insert into probes (probe_name, description, version, probe_query) values ('read_write_ratio', 'Read / Write on tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime,
  relname as table,
  seq_tup_read,
  idx_tup_fetch,
  seq_tup_read + idx_tup_fetch AS n_tup_read,
  n_tup_ins, n_tup_upd, n_tup_del,
  100.0 * (seq_tup_read + idx_tup_fetch) / (n_tup_ins + n_tup_upd + n_tup_del + seq_tup_read + idx_tup_fetch) AS ratio
FROM pg_stat_user_tables
WHERE n_tup_ins + n_tup_upd + n_tup_del > 0;');

insert into probes (probe_name, description, version, probe_query) values ('database_stats', 'Database statistics', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_stat_database;');

insert into probes (probe_name, description, version, probe_query) values ('bgwriter_stats', 'Background writer statistics', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_bgwriter;');


insert into probes (probe_name, description, version, probe_query) values ('user_tables', 'Statistics of user tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_user_tables;');

insert into probes (probe_name, description, version, probe_query) values ('user_indexes', 'Statistics of user indexes', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * FROM pg_stat_user_indexes;');

insert into probes (probe_name, description, version, probe_query) values ('io_user_tables', 'I/O Statistics on all tables', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_statio_all_tables;');

insert into probes (probe_name, description, version, probe_query) values ('io_user_indexes', 'I/O Statistics on all indexes', '9.0', 'SELECT date_trunc(''seconds'', current_timestamp) as datetime, * from pg_statio_all_indexes;');
