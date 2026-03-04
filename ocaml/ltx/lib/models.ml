(* models.ml — LTX data model types *)

type ltx_node = {
  id:       string;
  name:     string;
  role:     string;
  delay:    int;
  location: string;
}

type ltx_segment_template = {
  seg_type: string;
  q:        int;
}

type ltx_plan = {
  v:        int;
  title:    string;
  start:    string;
  quantum:  int;
  mode:     string;
  nodes:    ltx_node list;
  segments: ltx_segment_template list;
}

type ltx_timed_segment = {
  seg_type:  string;
  q:         int;
  start_iso: string;
  end_iso:   string;
  dur_min:   int;
}

type ltx_node_url = {
  node_id: string;
  name:    string;
  role:    string;
  url:     string;
}

type delay_matrix_entry = {
  from_id:       string;
  from_name:     string;
  to_id:         string;
  to_name:       string;
  delay_seconds: int;
}
