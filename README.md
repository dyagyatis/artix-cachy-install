# Artix + CachyOS Installer

Автоматический скрипт для установки Artix Linux с ядром CachyOS, NVIDIA-драйверами и окружением Niri.

## Использование
1. Загрузитесь с любого Arch/Artix Live ISO.
2. Скачайте скрипт:
   `curl -O https://raw.githubusercontent.com/dyagyatis/artix-cachy-install/main/install.sh`
3. Сделайте исполняемым и запустите:
   `chmod +x install.sh && sudo ./install.sh`

## Что делает скрипт:
- Автоматически размечает диск (GPT + EFI).
- Настраивает зеркала Artix и CachyOS.
- Устанавливает систему с Runit и CachyOS EEVDF ядром.
- Настраивает NVIDIA Open драйверы (ветка 610).
