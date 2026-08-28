pub mod decay;
pub mod forget;
pub mod protect;
pub mod rehabilitate;
pub mod strengthen;
pub mod suppress;

#[derive(Debug, Clone, Copy)]
pub enum PlasticityAction {
    Strengthen,
    Decay,
    Suppress,
    Protect,
    Rehabilitate,
    Forget,
}
