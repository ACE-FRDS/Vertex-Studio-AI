pub trait DirectNativeModel {
    fn accepts_vxn_native(&self) -> bool;
    fn protocol_version(&self) -> Option<String>;
}
