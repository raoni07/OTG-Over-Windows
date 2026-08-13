# ArkOS/dArkOS USB Network Manager (Internet + SSH)

Script para dispositivos ArkOS/dArkOS (R36S e compatíveis) que ativa uma rede USB via OTG diretamente do menu de ferramentas do console, oferecendo **SSH** e **compartilhamento de Internet do Windows** ao mesmo tempo — tudo controlado por uma interface em `dialog`, navegável pelo joystick do próprio aparelho.

## Sobre

Ao conectar o console num PC com Windows via cabo USB, o script cria um gadget USB (RNDIS/ECM) que aparece no Windows como um adaptador de rede. Se o **Compartilhamento de Conexão com a Internet (ICS)** estiver ativado nesse adaptador, o console recebe IP via DHCP do próprio Windows e passa a ter acesso à Internet — além de já subir o serviço SSH automaticamente, para acesso remoto via `ssh ark@<IP>`.

## Funcionalidades

- Cria gadget USB de rede (RNDIS, com fallback para ECM)
- Modo cliente DHCP: obtém IP automaticamente do compartilhamento de Internet do Windows (ICS)
- Detecta e tenta corrigir automaticamente IP inválido (APIPA / `169.254.x.x`)
- Sobe o serviço SSH automaticamente (`ssh`/`sshd`, com fallback manual)
- Teste de conectividade (ping) para confirmar se a Internet está realmente passando
- Verificação de status a qualquer momento (IP atual, Internet, SSH)
- Início automático no boot (via `systemd`), com opção de ativar/desativar pelo menu
- Rotação simples do log de boot, evitando crescimento indefinido no cartão SD
- Detecção de conflito com o gadget do script SSH-over-OTG original (rede isolada), evitando dois gadgets disputando a mesma porta USB
- Tela de instruções passo a passo para configurar o ICS no Windows
- Interface 100% navegável por joystick (via `gptokeyb`), sem precisar de teclado

## Requisitos

- ArkOS ou dArkOS instalado no dispositivo (testado em R36S)
- Suporte a USB OTG no hardware (porta USB-C/micro-USB com função de gadget)
- `dialog`, `gptokeyb` e módulos de kernel `libcomposite`, `usb_f_rndis`, `usb_f_ecm` (já presentes na maioria das imagens ArkOS/dArkOS)
- No PC: Windows com Compartilhamento de Conexão com a Internet (ICS) disponível no adaptador de rede

## Instalação

1. Copie `OTG Over Windows.sh` para a pasta de tools ou ports do seu ArkOS/dArkOS (geralmente `/roms/tools/` ou `/roms/ports/`).

## Uso

1. Conecte o console ao PC via cabo USB.
2. No Windows, ative o Compartilhamento de Conexão com a Internet no adaptador USB (o script tem uma tela de instruções passo a passo — opção **4** no menu).
3. No console, abra o script e selecione **Ativar Rede USB (Internet + SSH)**.
4. Aguarde o IP ser atribuído. Quando a Internet estiver OK, o próprio menu mostra o comando pronto:

   Senha padrão: `ark` (padrão do ArkOS/dArkOS).

### Menu

| Opção | Ação |
|---|---|
| Ativar/Desativar Rede USB | Liga ou derruba o gadget USB (pede confirmação ao desligar) |
| Verificar Status | Mostra IP atual, status da Internet e do SSH |
| Ativar/Desativar Início Automático | Cria/remove um serviço `systemd` para subir a rede sozinha no boot |
| Instruções para Windows | Passo a passo de como habilitar o ICS |

## Início automático (boot)

Ao ativar o início automático, o script registra um serviço `systemd` (`darkos-usbnet.service`) que roda `OTG_Over_Windows.sh --internet` a cada boot, registrando o resultado em `/roms/tools/OTG_Over_Windows.log` (com rotação automática ao passar de 1 MB).

## Solução de problemas

- **IP `169.254.x.x` ou nenhum IP:** o Windows não está compartilhando a Internet nesse adaptador. Revise o ICS (opção 5 do menu tem o passo a passo).
- **Interface `usb0` não aparece:** verifique se o cabo USB suporta dados (alguns cabos são só de energia) e se a porta do console tem suporte a modo gadget.
- **Rede ativa mas sem SSH:** confirme que o pacote de SSH está instalado e que o usuário `ark` existe no sistema.
- **Conflito com outro script de rede USB:** se você também usa a versão "SSH isolado" (rede fixa `192.168.7.x`, sem Internet), o script detecta o gadget concorrente e oferece desativá-lo antes de continuar.

## Créditos

Este projeto parte do script **[SSH-over-OTG-for-ArkOS](https://github.com/carrothu-cn/SSH-over-OTG-for-ArkOS)**, de [carrothu-cn](https://github.com/carrothu-cn) (licenciado sob GPL-3.0), que por sua vez cita como base o trabalho original de [u/AlternativeRoom4499 no r/R36S](https://www.reddit.com/r/R36S/comments/1kzwn5d/ssh_over_otg_on_arkos_installed_r36sc/).


## Licença

O projeto-base (SSH-over-OTG-for-ArkOS) é licenciado sob **GPL-3.0**. Como este script é um trabalho derivado dele, o mais consistente é distribuí-lo sob a mesma licença — ao criar o repositório no GitHub, use o template **"GNU General Public License v3.0"** na hora de gerar o arquivo `LICENSE`. *(Isso é só uma orientação prática, não assessoria jurídica — vale confirmar os termos da GPL-3.0 se tiver dúvida sobre como isso se aplica ao seu caso.)*

## Aviso

Este script mexe em configurações de baixo nível do sistema (gadget USB via `configfs`, módulos de kernel, serviços `systemd`). Use por sua conta e risco; revise o código antes de rodar como root, especialmente antes de habilitar o início automático.
