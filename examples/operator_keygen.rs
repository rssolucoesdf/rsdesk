// Gera o par de chaves do operador do RSDesk (acesso sem supervisao).
//
// Rode na maquina do tecnico. Grava a chave PRIVADA na pasta de configuracao do RSDesk (ou no
// caminho passado como primeiro argumento) e imprime a chave PUBLICA, que vai embutida no build
// Cliente pela variavel RSDESK_OPERATOR_PUBKEYS. Recusa sobrescrever uma chave existente.
//
//   cargo run --release --features flutter,hwcodec,vram --example operator_keygen

use hbb_common::{config::Config, sodiumoxide::crypto::sign};
use librustdesk::common::encode64;

fn main() {
    hbb_common::sodiumoxide::init().ok();
    let (pk, sk) = sign::gen_keypair();

    let out = std::env::args()
        .nth(1)
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| Config::path("operator_ed25519.key"));

    if out.exists() {
        eprintln!("Recusado: o arquivo ja existe: {}", out.display());
        std::process::exit(1);
    }
    if let Some(dir) = out.parent() {
        std::fs::create_dir_all(dir).ok();
    }
    if let Err(e) = std::fs::write(&out, encode64(sk.0)) {
        eprintln!("Falha ao gravar {}: {e}", out.display());
        std::process::exit(1);
    }

    println!("Chave privada gravada em: {}", out.display());
    println!("Guarde uma copia desta chave fora do PC (ela abre todos os clientes).");
    println!();
    println!("Chave publica para RSDESK_OPERATOR_PUBKEYS:");
    println!("{}", encode64(pk.0));
}
