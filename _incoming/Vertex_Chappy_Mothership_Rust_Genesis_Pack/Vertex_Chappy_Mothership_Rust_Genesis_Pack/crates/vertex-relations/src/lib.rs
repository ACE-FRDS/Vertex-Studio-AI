use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet, VecDeque},
    fs,
    path::Path,
};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub struct Edge {
    pub relation_type: String,
    pub source_id: String,
    pub target_id: String,
    #[serde(default)]
    pub metadata: Value,
}
#[derive(Debug, Clone, Serialize)]
pub struct Impact {
    pub root: String,
    pub max_depth: usize,
    pub nodes: Vec<String>,
    pub edges: Vec<Edge>,
}

pub fn edges_from_mothership_state(path: &Path) -> Result<Vec<Edge>> {
    let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;
    let v: Value = serde_json::from_str(text.trim_start_matches('\u{feff}'))?;
    let raw = v
        .pointer("/mothership_graph/edges")
        .cloned()
        .unwrap_or_else(|| Value::Array(vec![]));
    Ok(serde_json::from_value(raw)?)
}
pub fn impact(root: &str, max_depth: usize, edges: &[Edge]) -> Impact {
    let mut by_node: HashMap<&str, Vec<&Edge>> = HashMap::new();
    for e in edges {
        by_node.entry(&e.source_id).or_default().push(e);
        by_node.entry(&e.target_id).or_default().push(e);
    }
    let mut q = VecDeque::from([(root.to_string(), 0usize)]);
    let mut seen = HashSet::from([root.to_string()]);
    let mut out = Vec::new();
    let mut ek = HashSet::new();
    while let Some((n, d)) = q.pop_front() {
        if d >= max_depth {
            continue;
        }
        if let Some(list) = by_node.get(n.as_str()) {
            for e in list {
                let key = (
                    e.relation_type.clone(),
                    e.source_id.clone(),
                    e.target_id.clone(),
                );
                if ek.insert(key) {
                    out.push((*e).clone())
                }
                let other = if e.source_id == n {
                    &e.target_id
                } else {
                    &e.source_id
                };
                if seen.insert(other.clone()) {
                    q.push_back((other.clone(), d + 1));
                }
            }
        }
    }
    let mut nodes: Vec<_> = seen.into_iter().collect();
    nodes.sort();
    Impact {
        root: root.into(),
        max_depth,
        nodes,
        edges: out,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn traverses_both_directions() {
        let e = vec![
            Edge {
                relation_type: "A".into(),
                source_id: "x".into(),
                target_id: "y".into(),
                metadata: Value::Null,
            },
            Edge {
                relation_type: "B".into(),
                source_id: "z".into(),
                target_id: "y".into(),
                metadata: Value::Null,
            },
        ];
        let x = impact("x", 4, &e);
        assert_eq!(x.nodes.len(), 3);
        assert_eq!(x.edges.len(), 2);
    }
}
