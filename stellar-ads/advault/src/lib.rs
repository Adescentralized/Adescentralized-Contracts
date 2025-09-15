#![no_std]
use soroban_sdk::{
    contract, contracterror, contractimpl, contracttype, Address, BytesN, Env, Symbol,
};
use soroban_sdk::token::TokenClient;
use verifier_registry::VerifierRegistryClient;

// ---------- STORAGE ----------
#[derive(Clone)]
#[contracttype]
pub enum DataKey {
    Admin,
    Token,                     // Address do contrato do token (p.ex. Stellar Asset Contract)
    VerifierRegistry,          // Address do contrato VerifierRegistry
    PricePerEvent,             // i128 (preço fixo do protocolo por evento)
    SplitPublisherBps,         // u32
    SplitViewerBps,            // u32
    FeeBps,                    // u32 taxa do protocolo
    Campaign(BytesN<32>),      // Campaign
    EventSeen(BytesN<32>),     // bool (anti-replay)
    Paused,                    // bool (pausa global do protocolo)
}

// ---------- TIPOS ----------
#[derive(Clone)]
#[contracttype]
pub struct Campaign {
    pub advertiser: Address,
    pub budget: i128,
    pub spent: i128,
    pub status: Symbol, // "active" | "closed"
}

#[derive(Clone)]
#[contracttype]
pub struct Attestation {
    pub event_id: BytesN<32>,
    pub campaign_id: BytesN<32>,
    pub publisher: Address,
    pub viewer: Address,
    pub event_kind: Symbol, // "click" | "view" (MVP: "click")
    pub timestamp: u64,
    pub nonce: BytesN<32>,
}

// ---------- ERROS ----------
#[contracterror]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Err {
    NotAdmin = 1,
    InvalidSplit = 2,
    UnauthorizedVerifier = 3,
    CampaignNotFound = 4,
    CampaignClosed = 5,
    EventReplay = 6,
    InsufficientBudget = 7,
    InvalidParam = 8,
    ProtocolPaused = 9,
    PublisherNotAllowed = 10,
}

// ---------- HELPERS ----------
fn admin(e: &Env) -> Address {
    e.storage().instance().get::<_, Address>(&DataKey::Admin).unwrap()
}
fn must_admin(e: &Env) { admin(e).require_auth(); }
fn token(e: &Env) -> Address {
    e.storage().instance().get::<_, Address>(&DataKey::Token).unwrap()
}
fn token_client(e: &Env) -> TokenClient { TokenClient::new(e, &token(e)) }
fn price(e: &Env) -> i128 {
    e.storage().instance().get::<_, i128>(&DataKey::PricePerEvent).unwrap()
}
fn bps_mul(amount: i128, bps: u32) -> i128 { (amount * bps as i128) / 10_000i128 }
fn split_pub(e: &Env) -> u32 { e.storage().instance().get::<_, u32>(&DataKey::SplitPublisherBps).unwrap() }
fn split_view(e: &Env) -> u32 { e.storage().instance().get::<_, u32>(&DataKey::SplitViewerBps).unwrap() }
fn fee_bps(e: &Env) -> u32 { e.storage().instance().get::<_, u32>(&DataKey::FeeBps).unwrap() }
fn verifier_registry(e: &Env) -> Address {
    e.storage().instance().get::<_, Address>(&DataKey::VerifierRegistry).unwrap()
}
fn paused(e: &Env) -> bool {
    e.storage().instance().get::<_, bool>(&DataKey::Paused).unwrap_or(false)
}
fn set_paused(e: &Env, v: bool) { e.storage().instance().set(&DataKey::Paused, &v); }

fn get_campaign(e: &Env, id: &BytesN<32>) -> Option<Campaign> {
    e.storage().instance().get::<_, Campaign>(&DataKey::Campaign(id.clone()))
}
fn put_campaign(e: &Env, id: &BytesN<32>, c: &Campaign) {
    e.storage().instance().set(&DataKey::Campaign(id.clone()), c);
}

// ---------- EVENTOS ----------
#[derive(Clone)]
#[contracttype]
pub struct EvCampaignCreated { pub campaign_id: BytesN<32>, pub advertiser: Address, pub initial_deposit: i128 }
#[derive(Clone)]
#[contracttype]
pub struct EvDeposit { pub campaign_id: BytesN<32>, pub from: Address, pub amount: i128 }
#[derive(Clone)]
#[contracttype]
pub struct EvEventPaid {
    pub campaign_id: BytesN<32>, pub event_id: BytesN<32>,
    pub publisher: Address, pub viewer: Address,
    pub paid_pub: i128, pub paid_view: i128, pub fee: i128
}
#[derive(Clone)]
#[contracttype]
pub struct EvCampaignClosed { pub campaign_id: BytesN<32>, pub reason: Symbol }
#[derive(Clone)]
#[contracttype]
pub struct EvRefund { pub campaign_id: BytesN<32>, pub to: Address, pub amount: i128 }

// ---------- CONTRATO ----------
#[contract]
pub struct AdVault;

#[contractimpl]
impl AdVault {
    // ===== INIT & GOV =====
    pub fn init(
        e: Env,
        admin: Address,
        token: Address,
        verifier_registry: Address,
        price_per_event: i128,
        split_publisher_bps: u32,
        split_viewer_bps: u32,
        fee_bps: u32,
    ) -> Result<(), Err> {
        if split_publisher_bps as u64 + split_viewer_bps as u64 > 10_000 {
            return Err(Err::InvalidSplit);
        }
        e.storage().instance().set(&DataKey::Admin, &admin);
        e.storage().instance().set(&DataKey::Token, &token);
        e.storage().instance().set(&DataKey::VerifierRegistry, &verifier_registry);
        e.storage().instance().set(&DataKey::PricePerEvent, &price_per_event);
        e.storage().instance().set(&DataKey::SplitPublisherBps, &split_publisher_bps);
        e.storage().instance().set(&DataKey::SplitViewerBps, &split_viewer_bps);
        e.storage().instance().set(&DataKey::FeeBps, &fee_bps);
        e.storage().instance().set(&DataKey::Paused, &false);
        Ok(())
    }

    pub fn pause_protocol(e: Env) { must_admin(&e); set_paused(&e, true); }
    pub fn unpause_protocol(e: Env) { must_admin(&e); set_paused(&e, false); }
    pub fn is_protocol_paused(e: Env) -> bool { paused(&e) }

    pub fn set_price_per_event(e: Env, new_price: i128) -> Result<(), Err> {
        must_admin(&e);
        e.storage().instance().set(&DataKey::PricePerEvent, &new_price);
        Ok(())
    }
    pub fn set_splits(e: Env, pub_bps: u32, view_bps: u32) -> Result<(), Err> {
        must_admin(&e);
        if pub_bps as u64 + view_bps as u64 > 10_000 { return Err(Err::InvalidSplit); }
        e.storage().instance().set(&DataKey::SplitPublisherBps, &pub_bps);
        e.storage().instance().set(&DataKey::SplitViewerBps, &view_bps);
        Ok(())
    }
    pub fn set_fee_bps(e: Env, new_fee: u32) -> Result<(), Err> {
        must_admin(&e);
        e.storage().instance().set(&DataKey::FeeBps, &new_fee);
        Ok(())
    }

    // ===== CAMPANHAS =====
    /// cria campanha com ID definido pelo cliente (hash) e depósito inicial opcional
    pub fn create_campaign(e: Env, campaign_id: BytesN<32>, advertiser: Address, initial_deposit: i128) -> Result<(), Err> {
        if paused(&e) { return Err(Err::ProtocolPaused); }

        advertiser.require_auth();
        if get_campaign(&e, &campaign_id).is_some() { return Err(Err::InvalidParam); }

        let c = Campaign { advertiser: advertiser.clone(), budget: 0, spent: 0, status: Symbol::new(&e, "active") };
        put_campaign(&e, &campaign_id, &c);

        if initial_deposit > 0 {
            let client = token_client(&e);
            client.transfer(&advertiser, &e.current_contract_address(), &initial_deposit);
            let mut cc = get_campaign(&e, &campaign_id).unwrap();
            cc.budget += initial_deposit;
            put_campaign(&e, &campaign_id, &cc);
        }

        e.events().publish((Symbol::new(&e, "CampaignCreated"),), EvCampaignCreated { campaign_id, advertiser, initial_deposit });
        Ok(())
    }

    pub fn deposit(e: Env, campaign_id: BytesN<32>, from: Address, amount: i128) -> Result<(), Err> {
        if paused(&e) { return Err(Err::ProtocolPaused); }
        from.require_auth();

        let mut c = get_campaign(&e, &campaign_id).ok_or(Err::CampaignNotFound)?;
        if c.status != Symbol::new(&e, "active") { return Err(Err::CampaignClosed); }

        let client = token_client(&e);
        client.transfer(&from, &e.current_contract_address(), &amount);
        c.budget += amount;
        put_campaign(&e, &campaign_id, &c);

        e.events().publish((Symbol::new(&e, "Deposit"),), EvDeposit { campaign_id, from, amount });
        Ok(())
    }

    /// fecha campanha (admin OU advertiser — aqui: admin para simplificar operações de hackathon)
    pub fn close_campaign(e: Env, campaign_id: BytesN<32>, reason: Symbol) -> Result<(), Err> {
        must_admin(&e);
        let mut c = get_campaign(&e, &campaign_id).ok_or(Err::CampaignNotFound)?;
        c.status = Symbol::new(&e, "closed");
        put_campaign(&e, &campaign_id, &c);
        e.events().publish((Symbol::new(&e, "CampaignClosed"),), EvCampaignClosed { campaign_id, reason });
        Ok(())
    }

    /// devolve não-gasto após close
    pub fn refund_unspent(e: Env, campaign_id: BytesN<32>, to: Address) -> Result<i128, Err> {
        must_admin(&e);
        let mut c = get_campaign(&e, &campaign_id).ok_or(Err::CampaignNotFound)?;
        if c.status != Symbol::new(&e, "closed") { return Err(Err::InvalidParam); }
        let unspent = c.budget - c.spent;
        if unspent <= 0 { return Ok(0); }
        c.budget -= unspent;
        put_campaign(&e, &campaign_id, &c);

        let client = token_client(&e);
        client.transfer(&e.current_contract_address(), &to, &unspent);
        e.events().publish((Symbol::new(&e, "Refund"),), EvRefund { campaign_id, to, amount: unspent });
        Ok(unspent)
    }

    // ===== PAGAMENTO POR EVENTO =====
    /// O verificador chama essa função (ele deve ASSINAR a tx).
    /// split e taxa do protocolo são definidos no próprio contrato (admin).
    pub fn submit_event(e: Env, att: Attestation, verifier: Address) -> Result<(i128,i128,i128), Err> {
        if paused(&e) { return Err(Err::ProtocolPaused); }

        // 1) verificador precisa estar autorizado no VerifierRegistry E assinar a tx
        verifier.require_auth();
        if !Self::is_authorized_verifier(&e, &verifier) {
            return Err(Err::UnauthorizedVerifier);
        }

        // 2) anti-replay
        let seen = e.storage().instance().get::<_, bool>(&DataKey::EventSeen(att.event_id.clone())).unwrap_or(false);
        if seen { return Err(Err::EventReplay); }

        // 3) campanha e publisher
        let mut c = get_campaign(&e, &att.campaign_id).ok_or(Err::CampaignNotFound)?;
        if c.status != Symbol::new(&e, "active") { return Err(Err::CampaignClosed); }
        if !Self::is_publisher_allowed_global(&e, &att.publisher) {
            return Err(Err::PublisherNotAllowed);
        }

        // 4) cálculo dos valores
        let total = price(&e);
        let pub_bps = split_pub(&e);
        let view_bps = split_view(&e);
        let fee_bps = fee_bps(&e);
        if (pub_bps as u64 + view_bps as u64) > 10_000 { return Err(Err::InvalidSplit); }

        let fee = bps_mul(total, fee_bps);
        let paid_pub = bps_mul(total, pub_bps);
        let paid_view = bps_mul(total, view_bps);
        if fee + paid_pub + paid_view != total { return Err(Err::InvalidParam); }

        if c.spent + total > c.budget { return Err(Err::InsufficientBudget); }

        // 5) transferências na hora
        let client = token_client(&e);
        client.transfer(&e.current_contract_address(), &att.publisher, &paid_pub);
        client.transfer(&e.current_contract_address(), &att.viewer, &paid_view);
        if fee > 0 {
            client.transfer(&e.current_contract_address(), &admin(&e), &fee);
        }

        c.spent += total;
        put_campaign(&e, &att.campaign_id, &c);
        e.storage().instance().set(&DataKey::EventSeen(att.event_id.clone()), &true);

        e.events().publish((Symbol::new(&e, "EventPaid"),), EvEventPaid {
            campaign_id: att.campaign_id.clone(),
            event_id: att.event_id.clone(),
            publisher: att.publisher.clone(),
            viewer: att.viewer.clone(),
            paid_pub, paid_view, fee
        });

        Ok((paid_pub, paid_view, fee))
    }

    // ===== Getters úteis =====
    pub fn get_campaign(e: Env, campaign_id: BytesN<32>) -> Option<Campaign> {
        get_campaign(&e, &campaign_id)
    }
    pub fn get_config(e: Env) -> (Address, Address, i128, u32, u32, u32, bool) {
        // (admin, token, price, pub_bps, view_bps, fee_bps, paused)
        (admin(&e), token(&e), price(&e), split_pub(&e), split_view(&e), fee_bps(&e), paused(&e))
    }

    // ===== Integração com VerifierRegistry =====
    fn is_authorized_verifier(e: &Env, addr: &Address) -> bool {
        let reg = verifier_registry(e);
        let client = VerifierRegistryClient::new(e, &reg);
        client.is_verifier(addr)
    }

    fn is_publisher_allowed_global(e: &Env, pub_addr: &Address) -> bool {
        let reg = verifier_registry(e);
        let client = VerifierRegistryClient::new(e, &reg);
        client.is_publisher_allowed(pub_addr)
    }

}
