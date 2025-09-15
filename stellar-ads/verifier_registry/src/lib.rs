#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, Address, Env,
};

#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Owner,
    Verifier(Address),   // bool
    Publisher(Address),  // bool
    Paused,              // bool
}

#[contracterror]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Err {
    NotOwner = 1,
}

#[contract]
pub struct VerifierRegistry;

#[contractimpl]
impl VerifierRegistry {
    pub fn init(e: Env, owner: Address) {
        e.storage().instance().set(&DataKey::Owner, &owner);
        e.storage().instance().set(&DataKey::Paused, &false);
    }

    // ---------- Helpers privados ----------
    fn get_owner(e: &Env) -> Address {
        e.storage().instance().get::<_, Address>(&DataKey::Owner).unwrap()
    }

    fn must_owner(e: &Env) {
        Self::get_owner(e).require_auth();
    }

    // ---------- Governança ----------
    pub fn pause(e: Env) {
        Self::must_owner(&e);
        e.storage().instance().set(&DataKey::Paused, &true);
    }

    pub fn unpause(e: Env) {
        Self::must_owner(&e);
        e.storage().instance().set(&DataKey::Paused, &false);
    }

    pub fn is_paused(e: Env) -> bool {
        e.storage().instance().get::<_, bool>(&DataKey::Paused).unwrap()
    }

    // ---------- Verifiers ----------
    pub fn add_verifier(e: Env, v: Address) -> Result<(), Err> {
        Self::must_owner(&e);
        e.storage().instance().set(&DataKey::Verifier(v), &true);
        Ok(())
    }

    pub fn remove_verifier(e: Env, v: Address) -> Result<(), Err> {
        Self::must_owner(&e);
        e.storage().instance().set(&DataKey::Verifier(v), &false);
        Ok(())
    }

    pub fn is_verifier(e: Env, v: Address) -> bool {
        e.storage().instance().get::<_, bool>(&DataKey::Verifier(v)).unwrap_or(false)
    }

    // ---------- Publishers (opcional) ----------
    pub fn set_publisher_status(e: Env, p: Address, allowed: bool) -> Result<(), Err> {
        Self::must_owner(&e);
        e.storage().instance().set(&DataKey::Publisher(p), &allowed);
        Ok(())
    }

    pub fn is_publisher_allowed(e: Env, p: Address) -> bool {
        e.storage().instance().get::<_, bool>(&DataKey::Publisher(p)).unwrap_or(true)
    }

    // ---------- Getter público ----------
    pub fn owner(e: Env) -> Address {
        Self::get_owner(&e)
    }
}
