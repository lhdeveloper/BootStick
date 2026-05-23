# BootStick

Assistente interativo em Terminal para criar pendrive ou SSD bootável de instalação do macOS em projetos Hackintosh (OpenCore).

O fluxo manual costuma envolver vários comandos (`diskutil`, `createinstallmedia`, montar EFI, etc.). O BootStick guia esse processo passo a passo com um menu simples (letras A–Z).

---

## Para que serve

Criar mídia de instalação bootável do macOS em disco externo e preparar a partição EFI para copiar a pasta OpenCore — sem precisar decorar ou digitar os comandos manualmente.

---

## O que faz

| Etapa | Ação |
|-------|------|
| **D** | Selecionar disco USB/SSD externo |
| **F** | Formatar em GPT + Mac OS Extended |
| **I** | Escolher instalador em `/Applications` |
| **B** | Criar mídia bootável |
| **E** | Montar e abrir EFI no Finder |

Detecções automáticas:

- Discos externos (USB, Thunderbolt, etc.)
- Instaladores com `createinstallmedia` (PT/EN: `Instalação do macOS Tahoe`, `Install macOS Sequoia`, …)
- Volume já formatado no disco (pula formatação se existir `Install macOS` em **JHFS+**)
- Bloqueio de APFS no pendrive (incompatível com `createinstallmedia` em versões recentes)

---

## Requisitos

- macOS real (host Apple)
- Instalador macOS em `/Applications`
- Pendrive ou SSD externo — mínimo ~16 GB (recomendado 32 GB+)
- Senha de administrador (`sudo`)
- OpenCore — o BootStick não gera EFI; após o processo, copie sua pasta `EFI` manualmente na partição montada (**E**)

---

## Uso

```bash
chmod +x BootStick.command
./BootStick.command
```

Fluxo típico: **D → F → I → B → E**

---

## Avisos

- Apaga todos os dados do disco selecionado na formatação (**F**).
- Não substitui config.plist, ACPI, kexts ou USBMap — apenas a mídia de instalação.
- Use por sua conta e risco; sempre confira o disco antes de formatar.
