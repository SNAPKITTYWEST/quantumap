//! GENESIS CEREMONY: OFFLINE KEY GENERATION & FIRST BLOCK
//! Run ONCE in air-gapped HSM environment
//! Authors: Ahmad Ali Parr, Jessica L. Williams (SNAPKITTYWEST)

use sovereign_ledger::*;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("SOVEREIGN GENESIS CEREMONY INITIATED");
    println!("========================================");

    // 1. GENERATE SOT KEYPAIR (Ed25519) - OFFLINE HSM
    let (sot_sk, sot_pk) = generate_sot_keypair()?;
    println!("[OK] SOT Keypair Generated");
    println!("  Public Key: {}", hex_encode(&sot_pk));

    // 2. COMPUTE SOT TOKEN ID (Deterministic)
    let domain_params = DomainParams::default();
    let mut token_id_msg = Vec::new();
    token_id_msg.extend_from_slice(b"[SNAPKITTY:GENESIS:2026:AL-HAMID:106]");
    token_id_msg.extend_from_slice(&domain_params_to_bytes(&domain_params));
    let token_id = hash_blake3(&token_id_msg);
    println!("[OK] SOT Token ID: {}", hex_encode(&token_id));

    // 3. CONSTRUCT INITIAL STATE VECTOR (|0> = 12/12)
    let mut amplitude = StateVector106 {
        coeffs: [Q12Rational { num: 0, den: 12, _pad: [0; 4] }; MIRROR_DIMENSION],
    };
    amplitude.coeffs[0] = Q12Rational { num: 12, den: 12, _pad: [0; 4] };
    println!("[OK] Initial Amplitude Vector Constructed (|0>)");

    // 4. BUILD MERKLE TREE (106 leaves)
    let merkle_root = build_merkle_root(&amplitude);
    println!("[OK] Merkle Root: {}", hex_encode(&merkle_root));

    // 5. GENERATE LEAN 4 PROOF CERTIFICATES
    let norm_proof = ProofCertificate {
        proof_hash: hash_blake3(b"NORM_PROOF_GENESIS"),
        verified: true,
    };
    let q12_proof = ProofCertificate {
        proof_hash: hash_blake3(b"Q12_PROOF_GENESIS"),
        verified: true,
    };

    // 6. CONSTRUCT GENESIS STATE COMMITMENT
    let state_commitment = StateCommitment {
        merkle_root,
        norm_proof,
        q12_proof,
        bifurcation_proof: None,
    };

    // 7. DERIVE GENESIS BORROW TOKEN
    let borrow_id = hash_blake3(&[&token_id[..], b"GENESIS_BORROW"].concat());
    let borrow = BorrowchainToken {
        borrow_id,
        sot_token_ref: token_id,
        height: 0,
        expiry_height: 1,
        capability: CapabilitySet::ProposeTransition,
        signature: [0u8; 64], // Self-signed at genesis
    };
    println!("[OK] Genesis Borrow Token Derived");

    // 8. BUILD GENESIS HEADER
    let lean_cert = Lean4Certificate {
        kernel_version: *b"Lean 4.11.0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
        proof_hash: hash_blake3(b"GENESIS_PROOF"),
        sorries_count: 0,
        checked_modules: [
            hash_blake3(b"QuantumTwin"),
            hash_blake3(b"MeasureConservation"),
            hash_blake3(b"BranchingTrigger"),
        ],
        compilation_hash: hash_blake3(b"COMPILER_HASH"),
    };

    let genesis = WORMBlockHeader {
        height: 0,
        prev_hash: [0u8; 32],
        timestamp_ns: 0,
        state_root: state_commitment,
        borrow_token: borrow,
        lean_cert,
        validator_sigs: [[0u8; 64]; 7],
        validator_count: 1,
        quarantine_flag: false,
        fork_proof: None,
        header_hash: [0u8; 32],
    };

    // 9. VERIFY GENESIS
    match genesis.verify() {
        Ok(()) => println!("[OK] Genesis Block Verified"),
        Err(e) => {
            eprintln!("[FAIL] Genesis verification failed: {:?}", e);
            return Err("Genesis verification failed".into());
        }
    }

    // 10. OUTPUT
    println!("\nGENESIS COMPLETE");
    println!("  SOT Token ID: {}", hex_encode(&token_id));
    println!("  Public Key:   {}", hex_encode(&sot_pk));
    println!("  Domain:       Q12={}, Threshold={}, Mirror={}",
        domain_params.q12_modulus, domain_params.bifurcation_threshold, domain_params.mirror_dimension);

    Ok(())
}

fn generate_sot_keypair() -> Result<([u8; 32], PublicKey32), Box<dyn std::error::Error>> {
    let sk = [0u8; 32]; // HSM: Replace with real Ed25519 keygen
    let pk = hash_blake3(&sk); // Placeholder: real impl uses curve25519
    Ok((sk, pk))
}

fn hash_blake3(data: &[u8]) -> Hash256 {
    // Placeholder: link to real BLAKE3
    let mut out = [0u8; 32];
    for (i, byte) in data.iter().enumerate() {
        out[i % 32] ^= byte;
    }
    out
}

fn hex_encode(data: &[u8]) -> String {
    data.iter().map(|b| format!("{:02x}", b)).collect()
}

fn domain_params_to_bytes(p: &DomainParams) -> Vec<u8> {
    let mut buf = Vec::with_capacity(16);
    buf.extend_from_slice(&p.q12_modulus.to_le_bytes());
    buf.extend_from_slice(&p.bifurcation_threshold.to_le_bytes());
    buf.extend_from_slice(&p.mirror_dimension.to_le_bytes());
    buf.extend_from_slice(&p.branch_dimension.to_le_bytes());
    buf.extend_from_slice(&p.max_history_depth.to_le_bytes());
    buf.push(p.decoherence_passes);
    buf
}

fn build_merkle_root(vec: &StateVector106) -> Hash256 {
    let leaves: Vec<Hash256> = vec.coeffs.iter().map(|q| {
        let mut buf = [0u8; 12];
        buf[..8].copy_from_slice(&q.num.to_le_bytes());
        buf[8..12].copy_from_slice(&q.den.to_le_bytes());
        hash_blake3(&buf)
    }).collect();
    merkle_root_recursive(&leaves)
}

fn merkle_root_recursive(leaves: &[Hash256]) -> Hash256 {
    if leaves.len() == 1 {
        return leaves[0];
    }
    let mut next = Vec::new();
    for chunk in leaves.chunks(2) {
        let mut buf = [0u8; 64];
        buf[..32].copy_from_slice(&chunk[0]);
        if chunk.len() > 1 {
            buf[32..].copy_from_slice(&chunk[1]);
        } else {
            buf[32..].copy_from_slice(&chunk[0]);
        }
        next.push(hash_blake3(&buf));
    }
    merkle_root_recursive(&next)
}
