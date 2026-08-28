use crate::error::{VxnError,VxnResult};
pub trait ComputeBackend:Send+Sync{fn name(&self)->&str;fn add_i64(&self,a:i64,b:i64)->VxnResult<i64>;}
pub struct CpuBackend;impl ComputeBackend for CpuBackend{fn name(&self)->&str{"cpu"}fn add_i64(&self,a:i64,b:i64)->VxnResult<i64>{Ok(a+b)}}
pub struct GpuBackend;impl ComputeBackend for GpuBackend{fn name(&self)->&str{"gpu"}fn add_i64(&self,_:i64,_:i64)->VxnResult<i64>{Err(VxnError::Unsupported("GPU backend contract exists; v0.1 reference backend is not wired to CUDA/ROCm".into()))}}
