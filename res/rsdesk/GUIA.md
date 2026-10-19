# Guia do RSDesk

RSDesk é a sua versão do RustDesk, para suporte remoto. Conecta só no seu servidor.

## 1. Os dois aplicativos

| Aplicativo | Onde instalar | Para quê |
|---|---|---|
| **RSDesk Cliente** | nas máquinas dos seus clientes | só recebe conexão; você acessa sem senha |
| **RSDesk Servidor** | no seu PC (técnico) | app completo, para acessar os clientes |

Nunca instale o Servidor na máquina de um cliente.

Os instaladores ficam em `C:\RSDesk\dist`:
- `rsdesk-cliente-<versao>-x86_64.exe`
- `rsdesk-servidor-<versao>-x86_64.exe`

A versão aparece no topo da janela, ao lado do ícone (ex.: `RSDesk 1.5.0.003`).

## 2. Instalar o Cliente numa máquina

1. Copie o `rsdesk-cliente-<versao>-x86_64.exe` para a máquina do cliente.
2. Abra o arquivo. Se o Windows mostrar o SmartScreen, clique em **Mais informações** → **Executar assim mesmo**.
3. Leia o aviso laranja (o dono precisa autorizar o acesso sem senha).
4. Clique em **Instalar** → **Aceitar e instalar** → **Sim** (UAC).

Depois de instalado, o RSDesk Cliente roda como serviço. Você acessa mesmo sem ninguém logado.

## 3. Acessar um cliente (sem senha)

1. No seu PC, abra o **RSDesk Servidor**.
2. Digite o **ID** do cliente e clique em **Conectar**.
3. A tela do cliente abre, **sem pedir senha**.

Como funciona: o Servidor tem a sua chave privada; o Cliente tem a chave pública embutida. O acesso é liberado pela assinatura da chave, não por senha. A senha de uso único continua valendo para suporte avulso.

Durante o acesso, a janela de conexão aparece na tela do cliente, e o ícone fica na bandeja do relógio.

## 4. O dono quer desligar o acesso sem senha

No Cliente: **Configurações → Segurança → Permitir acesso de suporte sem supervisão** (desmarque). Aí o acesso volta a pedir senha.

## 5. As chaves (importante)

- A **chave privada** fica em `C:\Users\<voce>\AppData\Roaming\RSDesk\config\operator_ed25519.key`, só no seu PC (Servidor).
- Ela abre **todos** os clientes. Guarde uma cópia num pendrive, fora do PC.
- A **chave pública** vai embutida no Cliente. Não é segredo.
- Nunca coloque a chave privada no GitHub.

Gerar um par novo de chaves (só se precisar trocar):

```
cargo run --release --features flutter,hwcodec,vram --example operator_keygen
```

Ele mostra a chave pública para usar no build do Cliente (variável `RSDESK_OPERATOR_PUBKEYS`).

## 6. Gerar um build novo (quando o RustDesk lançar versão nova)

1. Atualize o código do fork (merge da nova tag do RustDesk).
2. Suba a versão em `flutter/lib/consts.dart` (`kRSBuildTag`, ex.: `1.5.0.004`).
3. Abra o ambiente de build (Rust, Flutter, vcpkg, LLVM no PATH; `VCPKG_ROOT` e `LIBCLANG_PATH` definidos).
4. Rode, na pasta do repositório:

```
powershell -File res\rsdesk\criar-apps.ps1 -PubKey "SUA_CHAVE_PUBLICA"
```

Isso gera os dois instaladores (Servidor e Cliente) em `C:\RSDesk\dist`.

Cuidado com o disco: o build completo precisa de muito espaço temporário. Tenha pelo menos 100 GB livres em C.

## 7. O servidor

- hbbs e hbbr rodam em Docker, no contêiner `10.0.0.217` (Proxmox 10.0.0.211).
- Arquivo: `/opt/rsdesk/docker-compose.yml`. Imagem `rustdesk/rustdesk-server:1.1.16`.
- IP público: `177.207.233.246`. Portas abertas no UniFi: TCP 21115, 21116, 21117 e UDP 21116.
- Reiniciar: `cd /opt/rsdesk && docker compose restart`.

## 8. Antivírus e SmartScreen

O executável ainda **não tem assinatura digital**. Por isso o SmartScreen avisa e alguns antivírus (ex.: Bitdefender) bloqueiam.

Enquanto não há certificado:
- SmartScreen: **Mais informações → Executar assim mesmo**.
- Bitdefender: crie exceção para a **pasta de instalação** (`C:\Program Files\RSDesk`) e para o **serviço RSDesk**, não só para o exe.

Solução definitiva: comprar um certificado de assinatura de código. O build já está pronto para assinar: defina `RSDESK_SIGN_PFX` e `RSDESK_SIGN_PASS` antes de gerar, e o instalador sai assinado.

### Qual certificado comprar (pesquisa 2026)

| Opção | Preço/ano | Token USB? | Serve para uso comercial? |
|---|---|---|---|
| **Certum Standard OV (nuvem)** | ~€139 a €209 | não (nuvem) | **sim** — recomendado |
| SSL.com eSigner OV | ~US$ 180 | não (nuvem) | sim — bom para automação |
| Certum Open Source | ~€49 | não | **não** — risco de revogação se usar com clientes pagos |
| Azure Artifact Signing | ~US$ 10/mês | não | provavelmente **não elegível no Brasil** |
| EV (qualquer) | €329+ / US$ 900 | sim | caro e não vale mais a pena* |

Recomendado: **Certum Standard OV em nuvem** (pessoa física ou empresa, sem token). Link: shop.certum.eu/code-signing.html

Avisos importantes:
- *Desde 2024 o EV **não** libera o SmartScreen na hora (a Microsoft confirmou). Não pague EV só por isso.
- O OV também **não** zera o SmartScreen de imediato: a reputação cresce com os downloads. No começo ainda pode aparecer o aviso, com o seu nome como editor.
- **Assinar pode não parar o Bitdefender.** Ferramentas de acesso remoto costumam ser marcadas como "RemoteAdmin" pela heurística, mesmo assinadas. O caminho real: (1) assinar; (2) a cada versão, enviar o arquivo como **falso positivo** em bitdefender.com/business/submit; (3) enquanto isso, o cliente cria exceção da pasta e do serviço.
