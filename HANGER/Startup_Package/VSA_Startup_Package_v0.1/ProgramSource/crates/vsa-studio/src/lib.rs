use std::collections::{HashMap, HashSet};
use vsa_foundation::{Diagnostic, Id, VsaError, VsaResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectKind {
    DesktopApp,
    WebApp,
    DynamicWebsite,
    StaticWebsite,
    Mobile,
    ApiBackend,
    DatabaseSolution,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldType { Text, Integer, Decimal, Boolean, DateTime, Json, Blob }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldDef {
    pub id: Id,
    pub name: String,
    pub field_type: FieldType,
    pub required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TableDef {
    pub id: Id,
    pub name: String,
    pub fields: Vec<FieldDef>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ContextNode {
    pub id: Id,
    pub table_id: Id,
    pub alias: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RelationDef {
    pub id: Id,
    pub from_context: Id,
    pub from_field: Id,
    pub to_context: Id,
    pub to_field: Id,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PropertyValue { Text(String), Number(f64), Bool(bool) }

#[derive(Debug, Clone, PartialEq)]
pub struct LayoutNode {
    pub id: Id,
    pub kind: String,
    pub x: f32, pub y: f32, pub width: f32, pub height: f32,
    pub properties: HashMap<String, PropertyValue>,
    pub human_override: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScriptStep {
    pub step_id: String,
    pub label_ja: String,
    pub label_en: String,
    pub arguments: Vec<String>,
    pub returns: Option<String>,
    pub side_effects: Vec<String>,
    pub required_permissions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScriptDef {
    pub id: Id,
    pub name: String,
    pub steps: Vec<ScriptStep>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ThemeDef {
    pub id: Id,
    pub name: String,
    pub tokens: HashMap<String, String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssetDef {
    pub id: Id,
    pub name: String,
    pub mime: String,
    pub logical_path: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReportDef { pub id: Id, pub name: String, pub source_context: Option<Id> }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DocumentDef { pub id: Id, pub title: String, pub body: String }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MindMapNode { pub id: Id, pub text: String, pub parent: Option<Id> }

#[derive(Debug, Clone)]
pub struct VertexDefinition {
    pub id: Id,
    pub name: String,
    pub kind: ProjectKind,
    pub tables: Vec<TableDef>,
    pub contexts: Vec<ContextNode>,
    pub relations: Vec<RelationDef>,
    pub layouts: Vec<LayoutNode>,
    pub scripts: Vec<ScriptDef>,
    pub themes: Vec<ThemeDef>,
    pub assets: Vec<AssetDef>,
    pub reports: Vec<ReportDef>,
    pub documents: Vec<DocumentDef>,
    pub mind_map: Vec<MindMapNode>,
}

impl VertexDefinition {
    pub fn new(name: impl Into<String>, kind: ProjectKind) -> Self {
        Self {
            id: Id::new("solution"), name: name.into(), kind,
            tables: vec![], contexts: vec![], relations: vec![], layouts: vec![],
            scripts: vec![], themes: vec![], assets: vec![], reports: vec![],
            documents: vec![], mind_map: vec![],
        }
    }

    pub fn add_table(&mut self, name: impl Into<String>) -> Id {
        let id = Id::new("table");
        self.tables.push(TableDef { id: id.clone(), name: name.into(), fields: vec![] });
        id
    }

    pub fn add_field(&mut self, table: &Id, name: impl Into<String>, field_type: FieldType) -> VsaResult<Id> {
        let t = self.tables.iter_mut().find(|t| &t.id == table)
            .ok_or_else(|| VsaError::NotFound(format!("table {}", table.0)))?;
        let id = Id::new("field");
        t.fields.push(FieldDef { id: id.clone(), name: name.into(), field_type, required: false });
        Ok(id)
    }

    pub fn add_context(&mut self, table: &Id, alias: impl Into<String>) -> VsaResult<Id> {
        if !self.tables.iter().any(|t| &t.id == table) {
            return Err(VsaError::NotFound(format!("table {}", table.0)));
        }
        let id = Id::new("ctx");
        self.contexts.push(ContextNode { id: id.clone(), table_id: table.clone(), alias: alias.into() });
        Ok(id)
    }
}

pub fn relation_diagnostics(def: &VertexDefinition) -> Vec<Diagnostic> {
    let contexts: HashSet<_> = def.contexts.iter().map(|c| c.id.clone()).collect();
    let mut out = vec![];
    for r in &def.relations {
        if !contexts.contains(&r.from_context) || !contexts.contains(&r.to_context) {
            out.push(Diagnostic {
                severity:"error".into(),
                code:"REL_MISSING_CONTEXT".into(),
                message:format!("relation {} references missing context", r.id.0),
                locator:Some(r.id.0.clone()),
            });
        }
        if r.from_context == r.to_context {
            out.push(Diagnostic {
                severity:"warning".into(),
                code:"REL_SELF_CONTEXT".into(),
                message:"relation joins the same context node".into(),
                locator:Some(r.id.0.clone()),
            });
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn filemaker_like_first_field_flow() {
        let mut s = VertexDefinition::new("Test", ProjectKind::DatabaseSolution);
        let t = s.add_table("Customer");
        let f = s.add_field(&t, "name", FieldType::Text).unwrap();
        assert!(s.tables[0].fields.iter().any(|x| x.id == f));
    }
}
