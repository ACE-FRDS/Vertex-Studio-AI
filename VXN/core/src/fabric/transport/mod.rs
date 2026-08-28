#[derive(Debug, Clone)]
pub enum TransportKind {
    SharedMemory,
    MemoryMappedFile,
    NamedPipe,
    Socket,
    Quic,
    Remote,
}

pub trait VxnTransport: Send + Sync {
    fn name(&self) -> &'static str;
    fn send(&self, frame: &[u8]) -> Result<(), String>;
    fn receive(&self) -> Result<Vec<u8>, String>;
}
