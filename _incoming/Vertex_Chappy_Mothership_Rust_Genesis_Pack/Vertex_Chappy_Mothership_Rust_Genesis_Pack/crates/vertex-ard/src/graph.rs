use crate::model::{ArdEdge, ArdGraphDocument, ArdImpact, ArdNode, NodeKind};
use anyhow::{Context, Result};
use serde_json::{json, Value};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    fs,
    path::Path,
};

#[derive(Debug, Clone, Default)]
pub struct RelationGraph {
    pub document: ArdGraphDocument,
}

impl RelationGraph {
    pub fn new(document: ArdGraphDocument) -> Self {
        Self { document }
    }

    pub fn ensure_node(&mut self, id: impl Into<String>) {
        let id = id.into();
        self.document
            .nodes
            .entry(id.clone())
            .or_insert_with(|| ArdNode::inferred(id));
    }

    pub fn upsert_node(&mut self, node: ArdNode) {
        self.document.nodes.insert(node.id.clone(), node);
    }

    pub fn add_edge(&mut self, edge: ArdEdge) -> bool {
        let key = edge.key();

        if self
            .document
            .edges
            .iter()
            .any(|existing| existing.key() == key)
        {
            return false;
        }

        self.ensure_node(edge.source_id.clone());
        self.ensure_node(edge.target_id.clone());
        self.document.edges.push(edge);
        true
    }

    pub fn neighbors(&self, asset_id: &str) -> Vec<ArdEdge> {
        self.document
            .edges
            .iter()
            .filter(|edge| edge.source_id == asset_id || edge.target_id == asset_id)
            .cloned()
            .collect()
    }

    pub fn impact(&self, root: &str, max_depth: usize) -> ArdImpact {
        let mut by_node: BTreeMap<&str, Vec<&ArdEdge>> = BTreeMap::new();

        for edge in &self.document.edges {
            by_node
                .entry(edge.source_id.as_str())
                .or_default()
                .push(edge);
            by_node
                .entry(edge.target_id.as_str())
                .or_default()
                .push(edge);
        }

        let mut queue = VecDeque::from([(root.to_owned(), 0usize)]);
        let mut seen_nodes = BTreeSet::from([root.to_owned()]);
        let mut seen_edges = BTreeSet::new();
        let mut edges = Vec::new();

        while let Some((current, depth)) = queue.pop_front() {
            if depth >= max_depth {
                continue;
            }

            if let Some(adjacent) = by_node.get(current.as_str()) {
                for edge in adjacent {
                    let key = edge.key();

                    if seen_edges.insert(key) {
                        edges.push((*edge).clone());
                    }

                    let other = if edge.source_id == current {
                        &edge.target_id
                    } else {
                        &edge.source_id
                    };

                    if seen_nodes.insert(other.clone()) {
                        queue.push_back((other.clone(), depth + 1));
                    }
                }
            }
        }

        let nodes = seen_nodes
            .into_iter()
            .map(|id| {
                self.document
                    .nodes
                    .get(&id)
                    .cloned()
                    .unwrap_or_else(|| ArdNode::inferred(id))
            })
            .collect();

        ArdImpact {
            root: root.to_owned(),
            max_depth,
            nodes,
            edges,
        }
    }

    pub fn import_mothership_state(&mut self, path: &Path) -> Result<ImportReport> {
        let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;

        let value: Value = serde_json::from_str(text.trim_start_matches('\u{feff}'))
            .with_context(|| format!("parse {}", path.display()))?;

        let edges = value
            .pointer("/mothership_graph/edges")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();

        let mut report = ImportReport::default();

        for raw in edges {
            let Some(source_id) = raw.get("source_id").and_then(Value::as_str) else {
                continue;
            };

            let Some(target_id) = raw.get("target_id").and_then(Value::as_str) else {
                continue;
            };

            let relation_type = raw
                .get("relation_type")
                .and_then(Value::as_str)
                .unwrap_or("RELATED_TO");

            let metadata = raw.get("metadata").cloned().unwrap_or(Value::Null);

            let source_before = self.document.nodes.contains_key(source_id);
            let target_before = self.document.nodes.contains_key(target_id);

            let added = self.add_edge(ArdEdge {
                relation_type: relation_type.to_owned(),
                source_id: source_id.to_owned(),
                target_id: target_id.to_owned(),
                metadata,
            });

            if added {
                report.edges_added += 1;
            }

            if !source_before {
                report.nodes_added += 1;
            }

            if !target_before && target_id != source_id {
                report.nodes_added += 1;
            }
        }

        Ok(report)
    }

    pub fn import_vur_registry(&mut self, path: &Path) -> Result<ImportReport> {
        let text = fs::read_to_string(path).with_context(|| format!("read {}", path.display()))?;

        let value: Value = serde_json::from_str(text.trim_start_matches('\u{feff}'))
            .with_context(|| format!("parse {}", path.display()))?;

        let mut report = ImportReport::default();

        if let Some(relations) = value.get("relations").and_then(Value::as_array) {
            for raw in relations {
                let Some(source_id) = raw.get("source_id").and_then(Value::as_str) else {
                    continue;
                };

                let Some(target_id) = raw.get("target_id").and_then(Value::as_str) else {
                    continue;
                };

                let relation_type = raw
                    .get("relation_type")
                    .and_then(Value::as_str)
                    .unwrap_or("RELATED_TO");

                if self.add_edge(ArdEdge {
                    relation_type: relation_type.to_owned(),
                    source_id: source_id.to_owned(),
                    target_id: target_id.to_owned(),
                    metadata: raw.clone(),
                }) {
                    report.edges_added += 1;
                }
            }
        }

        if let Some(units) = value.get("units").and_then(Value::as_array) {
            for unit in units {
                let Some(unit_id) = unit.get("unit_id").and_then(Value::as_str) else {
                    continue;
                };

                let unit_node = ArdNode {
                    id: unit_id.to_owned(),
                    kind: NodeKind::Unit,
                    label: unit.get("name").and_then(Value::as_str).map(str::to_owned),
                    metadata: unit.clone(),
                };

                let was_new = !self.document.nodes.contains_key(unit_id);
                self.upsert_node(unit_node);

                if was_new {
                    report.nodes_added += 1;
                }

                if let Some(vcells) = unit.get("vcells").and_then(Value::as_array) {
                    for vcell in vcells {
                        let Some(vcell_id) = vcell.as_str() else {
                            continue;
                        };

                        if self.add_edge(ArdEdge {
                            relation_type: "COMPOSED_OF".to_owned(),
                            source_id: unit_id.to_owned(),
                            target_id: vcell_id.to_owned(),
                            metadata: json!({"source":"VUR"}),
                        }) {
                            report.edges_added += 1;
                        }
                    }
                }
            }
        }

        if let Some(vcells) = value.get("vcells").and_then(Value::as_array) {
            for cell in vcells {
                let Some(vcell_id) = cell.get("vcell_id").and_then(Value::as_str) else {
                    continue;
                };

                let was_new = !self.document.nodes.contains_key(vcell_id);

                self.upsert_node(ArdNode {
                    id: vcell_id.to_owned(),
                    kind: NodeKind::VCell,
                    label: cell.get("name").and_then(Value::as_str).map(str::to_owned),
                    metadata: cell.clone(),
                });

                if was_new {
                    report.nodes_added += 1;
                }

                if let Some(derived) = cell
                    .pointer("/lineage/derived_from")
                    .and_then(Value::as_array)
                {
                    for parent in derived {
                        let Some(parent_id) = parent.as_str() else {
                            continue;
                        };

                        if self.add_edge(ArdEdge {
                            relation_type: "DERIVED_FROM".to_owned(),
                            source_id: vcell_id.to_owned(),
                            target_id: parent_id.to_owned(),
                            metadata: json!({"source":"VUR"}),
                        }) {
                            report.edges_added += 1;
                        }
                    }
                }
            }
        }

        Ok(report)
    }

    pub fn edge_count(&self) -> usize {
        self.document.edges.len()
    }

    pub fn node_count(&self) -> usize {
        self.document.nodes.len()
    }
}

#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct ImportReport {
    pub nodes_added: usize,
    pub edges_added: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relation_graph_deduplicates_edges() {
        let mut graph = RelationGraph::default();

        let edge = ArdEdge {
            relation_type: "COMPOSED_OF".to_owned(),
            source_id: "unit://a".to_owned(),
            target_id: "vcell://b".to_owned(),
            metadata: Value::Null,
        };

        assert!(graph.add_edge(edge.clone()));
        assert!(!graph.add_edge(edge));

        assert_eq!(graph.edge_count(), 1);
        assert_eq!(graph.node_count(), 2);
    }

    #[test]
    fn impact_walks_in_both_directions() {
        let mut graph = RelationGraph::default();

        graph.add_edge(ArdEdge {
            relation_type: "A".to_owned(),
            source_id: "project://x".to_owned(),
            target_id: "repo://y".to_owned(),
            metadata: Value::Null,
        });

        graph.add_edge(ArdEdge {
            relation_type: "B".to_owned(),
            source_id: "changeset://z".to_owned(),
            target_id: "project://x".to_owned(),
            metadata: Value::Null,
        });

        let impact = graph.impact("project://x", 4);

        assert_eq!(impact.nodes.len(), 3);
        assert_eq!(impact.edges.len(), 2);
    }
}
