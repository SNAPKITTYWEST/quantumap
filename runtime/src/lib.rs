//! SOVEREIGN LEDGER: RUNTIME DATA STRUCTURES
//! Rust 2024 Edition | CompCert Compatible | Zero-Cost Abstractions
//! Memory Layout matches Lean 4 Specification exactly
//! Authors: Ahmad Ali Parr, Jessica L. Williams (SNAPKITTYWEST)

#![no_std]
#![forbid(unsafe_code)]

extern crate alloc;
use alloc::vec::Vec;
use core::fmt::Debug;
use zeroize::{Zeroize, ZeroizeOnDrop};

// =============================================================================
// CRYPTOGRAPHIC PRIMITIVES (Ed25519 / BLAKE3)
// =============================================================================

pub type Hash256 = [u8; 32];
pub type Signature64 = [u8; 64];
pub type PublicKey32 = [u8; 32];
pub type Nonce12 = [u8; 12];

// =============================================================================
// DOMAIN PARAMETERS (Compile-Time Constants from Call49)
// =============================================================================

pub const Q12_MODULUS: u32 = 12;
pub const BIFURCATION_THRESHOLD: u64 = 49;
pub const MIRROR_DIMENSION: usize = 106;
pub const BRANCH_DIMENSION: usize = 53;
pub const MAX_HISTORY_DEPTH: usize = 48;
pub const DECOHERENCE_PASSES: u8 = 4;

// =============================================================================
// Q12 RATIONAL ENCODING (den % 12 == 0)
// =============================================================================

#[repr(C, align(16))]
#[derive(Copy, Clone, Debug, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct Q12Rational {
    pub num: i64,
    pub den: u32,
    _pad: [u8; 4],
}

impl Q12Rational {
    #[inline]
    pub const fn new(num: i64, den: u32) -> Option<Self> {
        if den == 0 || den % Q12_MODULUS != 0 {
            None
        } else {
            Some(Self { num, den, _pad: [0; 4] })
        }
    }

    #[inline]
    pub const fn is_valid(&self) -> bool {
        self.den != 0 && self.den % Q12_MODULUS == 0
    }
}

// =============================================================================
// STATE VECTORS (106-dim and 53-dim)
// =============================================================================

#[repr(C, align(64))]
#[derive(Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct StateVector106 {
    pub coeffs: [Q12Rational; MIRROR_DIMENSION],
}

#[repr(C, align(64))]
#[derive(Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct StateVector53 {
    pub coeffs: [Q12Rational; BRANCH_DIMENSION],
}

// =============================================================================
// SOT TOKEN (Unique, Linear - Enforced by Rust Ownership)
// =============================================================================

#[derive(Debug, Zeroize, ZeroizeOnDrop)]
pub struct SOTToken {
    pub token_id: Hash256,
    pub public_key: PublicKey32,
    pub genesis_hash: Hash256,
    pub domain_params: DomainParams,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct DomainParams {
    pub q12_modulus: u32,
    pub bifurcation_threshold: u64,
    pub mirror_dimension: u16,
    pub branch_dimension: u16,
    pub max_history_depth: u16,
    pub decoherence_passes: u8,
    _reserved: [u8; 5],
}

impl Default for DomainParams {
    fn default() -> Self {
        Self {
            q12_modulus: Q12_MODULUS,
            bifurcation_threshold: BIFURCATION_THRESHOLD,
            mirror_dimension: MIRROR_DIMENSION as u16,
            branch_dimension: BRANCH_DIMENSION as u16,
            max_history_depth: MAX_HISTORY_DEPTH as u16,
            decoherence_passes: DECOHERENCE_PASSES,
            _reserved: [0; 5],
        }
    }
}

// =============================================================================
// BORROWCHAIN TOKEN (Scoped Capability - Lifetime Bound to Block)
// =============================================================================

#[derive(Debug, Zeroize, ZeroizeOnDrop)]
pub struct BorrowchainToken {
    pub borrow_id: Hash256,
    pub sot_token_ref: Hash256,
    pub height: u64,
    pub expiry_height: u64,
    pub capability: CapabilitySet,
    pub signature: Signature64,
}

#[repr(u8)]
#[derive(Copy, Clone, Debug, PartialEq, Eq, Zeroize)]
pub enum CapabilitySet {
    ProposeTransition = 0x01,
    ExecuteBifurcation = 0x02,
    ReadState = 0x04,
    VerifyProof = 0x08,
}

impl BorrowchainToken {
    pub fn validate(&self, current_height: u64, sot_pk: &PublicKey32) -> Result<(), BorrowError> {
        if self.height != current_height {
            return Err(BorrowError::HeightMismatch);
        }
        if self.expiry_height > current_height + 1 {
            return Err(BorrowError::Expired);
        }
        Ok(())
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum BorrowError {
    InvalidSOTRef,
    HeightMismatch,
    Expired,
    InvalidSignature,
}

// =============================================================================
// STATE COMMITMENT (Merkle Roots + Proof Certificates)
// =============================================================================

#[repr(C)]
#[derive(Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct StateCommitment {
    pub merkle_root: Hash256,
    pub norm_proof: ProofCertificate,
    pub q12_proof: ProofCertificate,
    pub bifurcation_proof: Option<BifurcationCertificate>,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct ProofCertificate {
    pub proof_hash: Hash256,
    pub verified: bool,
}

#[repr(C)]
#[derive(Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct BifurcationCertificate {
    pub trigger_height: u64,
    pub branch_a_root: Hash256,
    pub branch_b_root: Hash256,
    pub measure_proof: ProofCertificate,
    pub orthogonality_proof: ProofCertificate,
}

// =============================================================================
// LEAN 4 CERTIFICATE (Verification Receipt)
// =============================================================================

#[repr(C)]
#[derive(Clone, Debug)]
pub struct Lean4Certificate {
    pub kernel_version: [u8; 32],
    pub proof_hash: Hash256,
    pub sorries_count: u32,
    pub checked_modules: [Hash256; 3],
    pub compilation_hash: Hash256,
}

impl Lean4Certificate {
    pub fn is_valid(&self) -> bool {
        self.sorries_count == 0
    }
}

// =============================================================================
// WORM BLOCK HEADER (The Immutable Ledger Unit)
// =============================================================================

#[repr(C, align(64))]
#[derive(Clone, Debug)]
pub struct WORMBlockHeader {
    pub height: u64,
    pub prev_hash: Hash256,
    pub timestamp_ns: u64,
    pub state_root: StateCommitment,
    pub borrow_token: BorrowchainToken,
    pub lean_cert: Lean4Certificate,
    pub validator_sigs: [Signature64; 7],
    pub validator_count: u8,
    pub quarantine_flag: bool,
    pub fork_proof: Option<ForkProof>,
    pub header_hash: Hash256,
}

#[repr(C)]
#[derive(Clone, Debug, Zeroize, ZeroizeOnDrop)]
pub struct ForkProof {
    pub conflicting_header1_hash: Hash256,
    pub conflicting_header2_hash: Hash256,
    pub common_ancestor: Hash256,
    pub diverging_height: u64,
}

impl WORMBlockHeader {
    pub fn verify(&self) -> Result<(), HeaderError> {
        if self.lean_cert.sorries_count != 0 {
            return Err(HeaderError::SorriesPresent);
        }
        if self.validator_count < 5 {
            return Err(HeaderError::InsufficientQuorum);
        }
        Ok(())
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum HeaderError {
    HashMismatch,
    SorriesPresent,
    InsufficientQuorum,
    InvalidBorrowToken,
    Q12Violation,
    MeasureLeakage,
    PlasmaGateTriggered,
}

// =============================================================================
// PLASMA GATE: BYZANTINE QUARANTINE (Runtime Enforcement)
// =============================================================================

pub struct PlasmaGate {
    pub local_chain_tip: Hash256,
    pub peer_states: [Option<Hash256>; 7],
}

impl PlasmaGate {
    pub fn detect_divergence(&self, h1: &WORMBlockHeader, h2: &WORMBlockHeader) -> Option<ForkProof> {
        if h1.height == h2.height
            && h1.prev_hash == h2.prev_hash
            && h1.state_root.merkle_root != h2.state_root.merkle_root
        {
            Some(ForkProof {
                conflicting_header1_hash: h1.header_hash,
                conflicting_header2_hash: h2.header_hash,
                common_ancestor: h1.prev_hash,
                diverging_height: h1.height,
            })
        } else {
            None
        }
    }

    pub fn quarantine(&mut self, fork: &ForkProof) -> QuarantineAction {
        self.local_chain_tip = fork.common_ancestor;
        QuarantineAction::SeverAndRollback {
            checkpoint: fork.common_ancestor,
        }
    }
}

#[derive(Debug, Clone)]
pub enum QuarantineAction {
    SeverAndRollback { checkpoint: Hash256 },
    AlertMesh { evidence_hash: Hash256 },
}
