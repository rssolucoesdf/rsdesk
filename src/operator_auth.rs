// RSDesk unattended-access via an operator key.
//
// A "Cliente" build (installed on a customer machine with the owner's consent) embeds one or more
// Ed25519 public keys at build time through the `RSDESK_OPERATOR_PUBKEYS` env var. The technician's
// "Servidor" build holds the matching private key in a file. On each connection the host (Cliente)
// sends a fresh random nonce in `Hash.operator_nonce`; the operator signs
// `DOMAIN || host_id || 0 || nonce` and puts the signature in `LoginRequest.operator_sig`. The host
// accepts it only over an end-to-end-encrypted stream and only when the signature matches one
// embedded key for this host's own id. This replaces the per-machine password for unattended
// access; the normal password / one-time-password flow is untouched and still runs for everyone
// else. Having keys embedded also forces the build into incoming-only mode (the Cliente role).
//
// A build with no embedded keys (the default and the Servidor build) is byte-for-byte unchanged on
// the wire: `nonce()` returns empty, `verify()` always returns None, and the operator side only
// signs when it actually holds a key file.

use base::message_proto::{message, Hash, Message};
use hbb_common::{
    config::Config,
    sodiumoxide::{crypto::sign, randombytes::randombytes},
};

const PUBKEYS: Option<&str> = option_env!("RSDESK_OPERATOR_PUBKEYS");
const DOMAIN: &[u8] = b"rsdesk-operator-login-v1\0";
const NONCE_LEN: usize = 32;
const OPERATOR_KEY_FILE: &str = "operator_ed25519.key";
/// Owner-facing option: set to "N" to refuse operator key logins on this machine.
pub const OPTION_ALLOW_OPERATOR: &str = "allow-operator-access";

/// Public keys embedded in a Cliente build (comma-separated base64 in `RSDESK_OPERATOR_PUBKEYS`).
/// Empty for a normal/Servidor build, which disables the whole feature.
fn embedded_keys() -> Vec<sign::PublicKey> {
    let Some(raw) = PUBKEYS else {
        return Vec::new();
    };
    raw.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .filter_map(crate::common::get_rs_pk)
        .collect()
}

/// Whether this build is a Cliente build (has operator keys and therefore accepts key logins and
/// runs incoming-only).
#[inline]
pub fn is_cliente_build() -> bool {
    PUBKEYS.map_or(false, |s| !s.trim().is_empty())
}

/// Called once at startup from `load_custom_client`: a Cliente build runs incoming-only.
pub fn apply_build_role() {
    if is_cliente_build() {
        hbb_common::config::HARD_SETTINGS
            .write()
            .unwrap()
            .entry("conn-type".to_owned())
            .or_insert_with(|| "incoming".to_owned());
    }
}

/// The per-connection nonce a Cliente host puts in `Hash.operator_nonce`. Empty on a non-Cliente
/// build, which keeps the wire format identical to upstream.
pub fn nonce() -> Vec<u8> {
    if is_cliente_build() {
        randombytes(NONCE_LEN)
    } else {
        Vec::new()
    }
}

fn signed_msg(host_id: &str, nonce: &[u8]) -> Vec<u8> {
    let mut m = Vec::with_capacity(DOMAIN.len() + host_id.len() + 1 + nonce.len());
    m.extend_from_slice(DOMAIN);
    m.extend_from_slice(host_id.as_bytes());
    m.push(0);
    m.extend_from_slice(nonce);
    m
}

/// Host side. Returns the index of the operator key that signed this login, or None.
///
/// Rejects unless the stream is end-to-end encrypted, the nonce is the exact length this host
/// generated, the signature is well formed, and it verifies against an embedded key for THIS
/// host's own id. This is pure given the key set, so `verify_with` is split out for tests.
pub fn verify(operator_sig: &[u8], hash: &Hash, secured: bool) -> Option<usize> {
    if !is_cliente_build() {
        return None;
    }
    if !secured {
        return None;
    }
    // The machine owner can turn unattended operator access off (default: on).
    if Config::get_option(OPTION_ALLOW_OPERATOR) == "N" {
        return None;
    }
    verify_with(&embedded_keys(), &Config::get_id(), operator_sig, hash)
}

fn verify_with(
    keys: &[sign::PublicKey],
    host_id: &str,
    operator_sig: &[u8],
    hash: &Hash,
) -> Option<usize> {
    if hash.operator_nonce.len() != NONCE_LEN {
        return None;
    }
    let sig = sign::Signature::from_bytes(operator_sig).ok()?;
    let msg = signed_msg(host_id, &hash.operator_nonce);
    keys.iter()
        .position(|pk| sign::verify_detached(&sig, &msg, pk))
}

/// Operator side. Signs the outgoing login with the local operator private key, if one exists.
///
/// No-op unless the stream is secured (so the peer id was cryptographically verified) and the host
/// actually sent a nonce. A build with no key file simply sends an unsigned login and falls back to
/// the password flow.
pub fn sign_login_msg(msg_out: &mut Message, host_id: &str, hash: &Hash, secured: bool) {
    if !secured || hash.operator_nonce.len() != NONCE_LEN {
        return;
    }
    let Some(sk) = load_secret_key() else {
        return;
    };
    let sig = sign::sign_detached(&signed_msg(host_id, &hash.operator_nonce), &sk);
    if let Some(message::Union::LoginRequest(lr)) = msg_out.union.as_mut() {
        lr.operator_sig = sig.to_bytes().to_vec().into();
    }
}

fn load_secret_key() -> Option<sign::SecretKey> {
    let path = Config::path(OPERATOR_KEY_FILE);
    let raw = std::fs::read_to_string(&path).ok()?;
    let bytes = crate::decode64(raw.trim()).ok()?;
    sign::SecretKey::from_slice(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use base::message_proto::LoginRequest;
    use hbb_common::sodiumoxide::{crypto::sign, randombytes::randombytes};

    fn mk_hash(nonce: &[u8]) -> Hash {
        let mut hash = Hash::new();
        hash.operator_nonce = nonce.to_vec().into();
        hash
    }

    #[test]
    fn accepts_a_correct_signature() {
        let (pk, sk) = sign::gen_keypair();
        let nonce = randombytes(NONCE_LEN);
        let sig = sign::sign_detached(&signed_msg("abc123", &nonce), &sk);
        assert_eq!(
            verify_with(&[pk], "abc123", &sig.to_bytes(), &mk_hash(&nonce)),
            Some(0)
        );
    }

    #[test]
    fn rejects_wrong_host_id_nonce_key_and_length() {
        let (pk, sk) = sign::gen_keypair();
        let (other_pk, _) = sign::gen_keypair();
        let nonce = randombytes(NONCE_LEN);
        let sig = sign::sign_detached(&signed_msg("abc123", &nonce), &sk);
        let good = sig.to_bytes();
        let keys = [pk];
        let other = [other_pk];

        // wrong host id
        assert_eq!(verify_with(&keys, "other-id", &good, &mk_hash(&nonce)), None);
        // wrong nonce
        assert_eq!(
            verify_with(&keys, "abc123", &good, &mk_hash(&randombytes(NONCE_LEN))),
            None
        );
        // unknown key
        assert_eq!(verify_with(&other, "abc123", &good, &mk_hash(&nonce)), None);
        // short nonce
        assert_eq!(verify_with(&keys, "abc123", &good, &mk_hash(b"too-short")), None);
        // malformed signature
        assert_eq!(verify_with(&keys, "abc123", b"not-a-sig", &mk_hash(&nonce)), None);
    }

    #[test]
    fn operator_does_not_sign_without_a_nonce() {
        let mut msg = Message::new();
        msg.set_login_request(LoginRequest::new());
        let hash = Hash::new(); // empty nonce
        sign_login_msg(&mut msg, "abc123", &hash, true);
        assert!(msg.login_request().operator_sig.is_empty());
    }
}
