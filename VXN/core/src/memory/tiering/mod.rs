#[derive(Debug, Clone, Copy)]
pub enum MemoryTier {
    HotRam,
    WarmRam,
    PersistentDb,
    Archive,
}
