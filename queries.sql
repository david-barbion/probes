
SELECT g.id, g.graph_name, g.description FROM graphs g
JOIN default_graphs dg ON (g.id = dg.id_graph)
JOIN probes p ON (p.id = dg.id_probe)
JOIN probes_in_sets pis ON (pis.id_probe = p.id)
JOIN probe_sets ps ON (ps.id = pis.id_set)
LEFT JOIN custom_graphs cg ON (cg.id_graph = g.id and cg.id_set = ps.id)
WHERE ps.nsp_name = 'adeo';

SELECT p.id, p.probe_name
 FROM probes p
  JOIN probes_in_sets pis ON (p.id = pis.id_probe)
  JOIN probe_sets ps ON (pis.id_set = ps.id)
 WHERE ps.nsp_name = 'adeo';


SELECT g.id, g.graph_name
 FROM graphs g
  JOIN default_graphs dg ON (g.id = dg.id_graph)
  JOIN probes p ON (p.id = dg.id_probe)
  JOIN probes_in_sets pis ON (p.id = pis.id_probe)
  JOIN probe_sets ps ON (pis.id_set = ps.id)
 WHERE ps.nsp_name = 'adeo';


SELECT datetime AS start,      
  datetime - lag(datetime, 1) over () as elapsed,
  checkpoints_timed - lag(checkpoints_timed, 1) over () as checkpoints_timed,
  checkpoints_req - lag(checkpoints_req, 1) over () as checkpoints_req,
  buffers_checkpoint - lag(buffers_checkpoint, 1) over () as buffers_checkpoint,
  buffers_clean - lag(buffers_clean, 1) over () as buffers_clean,
  maxwritten_clean - lag(maxwritten_clean, 1) over () as maxwritten_clean,
  buffers_backend - lag(buffers_backend, 1) over () as buffers_backend,
  buffers_alloc - lag(buffers_alloc, 1) over () as buffers_alloc,
FROM bgwriter_stats
ORDER BY 1;
