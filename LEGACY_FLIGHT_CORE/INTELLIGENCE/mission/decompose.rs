use uuid::Uuid;

#[derive(Clone, Debug)]
pub struct AtomicTask {
    pub id: Uuid,
    pub title: String,
    pub estimated_units: u32,
    pub dependencies: Vec<Uuid>,
}

pub fn decompose(goals: &[String], reliable_units: u32) -> Vec<AtomicTask> {
    let chunk = reliable_units.max(1) as usize;
    let mut tasks = Vec::new();
    for (n, group) in goals.chunks(chunk).enumerate() {
        let dependencies = tasks.last()
            .map(|t: &AtomicTask| vec![t.id])
            .unwrap_or_default();
        tasks.push(AtomicTask {
            id: Uuid::new_v4(),
            title: format!("unit-{}: {}", n + 1, group.join(" / ")),
            estimated_units: group.len() as u32,
            dependencies,
        });
    }
    tasks
}
