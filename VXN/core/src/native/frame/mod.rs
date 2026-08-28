use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnFrameHeader {
    pub protocol_version: u16,
    pub frame_type: u16,
    pub priority: u8,
    pub flags: u32,
    pub sequence: u64,
    pub payload_len: u32,
    pub crc32: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VxnFrame {
    pub header: VxnFrameHeader,
    pub payload: Vec<u8>,
}
