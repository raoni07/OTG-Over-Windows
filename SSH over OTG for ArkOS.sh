#!/bin/bash
# ==============================================================================
# R36S Universal USB Network Manager (Internet + SSH) - v0.5
# Baseado em raoni07 - https://github.com/raoni07/OTG-Over-Windows
# e em SSH over OTG for ArkOS: https://github.com/carrothu-cn/SSH-over-OTG-for-ArkOS
#
# Changelog v0.6:
#   - Compatibilidade multi-firmware (ArkOS, dArkOS-RE, dArkOSen e derivados)
# ==============================================================================

if [ "$(id -u)" -ne 0 ]; then exec sudo "$0" "$@"; fi

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CURR_TTY="/dev/tty1"
APP_NAME="R36S USB Network"
SCRIPT_FULL_PATH="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "$SCRIPT_FULL_PATH")"
GADGET_DIR="/sys/kernel/config/usb_gadget/darkos_usbnet"
OTHER_GADGET_DIR="/sys/kernel/config/usb_gadget/arkos_ssh"
INTERFACE_NAME=""
AUTOSTART_FILE="/opt/system/.darkos_usbnet_autostart"
LOG_FILE="/roms/tools/OTG.over.Windows.log"
LOG_MAX_BYTES=1048576

CUSTOM_KEYS_FILE="/opt/system/.darkos_usbnet_keys.gptk"
SYSTEM_KEYS_FILE="/opt/inttools/keys.gptk"

STATIC_NETWORK="192.168.137"
STATIC_PREFIX="24"
STATIC_GATEWAY="${STATIC_NETWORK}.1"
STATIC_OCTET_FILE="/opt/system/.darkos_usbnet_octet"
DEFAULT_OCTET="7"
RESOLV_CONF="/etc/resolv.conf"
RESOLV_BACKUP_FILE="/opt/system/.darkos_usbnet_resolv_backup"
RESOLV_SYMLINK_FILE="/opt/system/.darkos_usbnet_resolv_symlink"

ES_SETTINGS_FILE="/home/ark/.emulationstation/es_settings.cfg"

SSHD_PID=""
DNS_APPLIED=0
FIRMWARE_ID="unknown"
LANG_ID="en"

IS_ACTIVE=0
HAS_VALID_IP=0
HAS_INTERNET=0
CURRENT_IP="N/A"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

LOG() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

RotateLogIfNeeded() {
    [ -f "$LOG_FILE" ] || return
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$size" -gt "$LOG_MAX_BYTES" ] && : > "$LOG_FILE"
}

DetectLanguage() {
    local loc=""

    if [ -f "$ES_SETTINGS_FILE" ]; then
        loc=$(grep -oP '(?<=<string name="Language" value=")[^"]+' "$ES_SETTINGS_FILE" 2>/dev/null | head -1)
    fi

    if [ -z "$loc" ]; then
        loc="${LC_ALL:-${LC_MESSAGES:-$LANG}}"
        if [ -z "$loc" ] && [ -f /etc/default/locale ]; then
            . /etc/default/locale 2>/dev/null || true
            loc="${LC_ALL:-${LC_MESSAGES:-$LANG}}"
        fi
    fi

    local code="${loc%%[_.@-]*}"
    code=$(printf '%s' "$code" | tr '[:upper:]' '[:lower:]')

    case "$code" in
        es) LANG_ID="es" ;;
        zh) LANG_ID="zh" ;;
        ja) LANG_ID="ja" ;;
        it) LANG_ID="it" ;;
        ru) LANG_ID="ru" ;;
        pt|ptbr|br) LANG_ID="pt" ;;
        *)  LANG_ID="en" ;;
    esac

    LOG "DetectLanguage: raw='$loc' code='$code' lang='$LANG_ID'"
}

SetLanguage() {
    case "$LANG_ID" in
        pt)
            T_DEPS="Erro fatal: dependência '%s' não encontrada."
            T_DEACTIVATING="Desativando rede USB...\nAguarde."
            T_OTHER_MODE="Rede USB de outro modo ativa.\n\nDesativá-la?"
            T_ACTIVATING="Ativando rede USB (Internet + SSH)...\nAguarde."
            T_ERR_CREATE="Erro: não foi possível criar %s\n\nVeja %s"
            T_ERR_FUNC="Erro: nenhuma função USB disponível.\n\nVeja %s"
            T_ERR_UDC="Erro: falha ao ativar UDC '%s'.\n\nVeja %s"
            T_ERR_IFACE="Erro: a interface USB não apareceu.\n\nVeja %s"
            T_ERR_IP="Erro ao aplicar IP.\n\nVeja %s"
            T_NET_ON="Rede USB ATIVADA.\n\nInterface: %s\nIP: %s\n\nLog: %s"
            T_AUTOSTART_OFF="Início automático DESATIVADO."
            T_AUTOSTART_ON="Início automático ATIVADO.\n\nServiço: darkos-usbnet.service\nModo: g_ether (boot)\nScript: %s"
            T_STATUS_ACTIVE_INT="Rede USB ATIVA\n\nInternet: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="Rede USB ATIVA\nIP não configurado."
            T_STATUS_OFF="Rede USB \Z1DESATIVADA\Zn."
            T_INSTRUCTIONS="=== INSTRUÇÕES PARA WINDOWS ===\n\n\Z11.\Zn Conecte o R36S via USB.\n\Z12.\Zn Painel de Controle > Rede > Conexões de Rede.\n\Z13.\Zn Clique no adaptador com Internet.\n\Z14.\Zn Propriedades > Compartilhamento > marcar.\n\Z15.\Zn Selecione 'Remote NDIS based Internet Sharing'."
            T_IP_UPDATED="IP atualizado para %s."
            T_IP_SAVED="IP salvo: %s."
            T_IP_MENU="Escolha o IP (192.168.137.X)\n\nGateway: %s"
            T_MENU_OFF="Desativar Rede USB"
            T_MENU_ON="Ativar Rede USB (Internet + SSH)"
            T_VERIFY="Verificar Status"
            T_CHANGE_IP="Alterar IP Fixo"
            T_AUTO_ON_LABEL="Ativar Início Automático"
            T_AUTO_OFF_LABEL="Desativar Início Automático"
            T_EXIT_KEEP="Sair (rede continua ativa)"
            T_EXIT="Sair"
            T_TITLE="Gerenciador de Rede USB v0.5"
            T_EMPTY="O menu retornou vazio.\nIsso costuma acontecer no primeiro clique.\n\nTentar novamente?"
            T_CONFIRM_OFF="Isso vai derrubar a rede USB.\n\nContinuar?"
            T_KEEP_ACTIVE="A rede USB continua ativa.\nExecute novamente para gerenciar."
            T_NET_OK="Status: OK"
            T_NET_NO="Status: \Z1SEM CONEXÃO\Zn"
            T_NET_UNAVAIL="Status: INDISPONÍVEL"
            T_NET_OFF="Status: \Z1DESATIVADA\Zn"
            T_LINE_ON="Rede USB: LIGADA | IP: %s"
            T_LINE_ON_NOIP="Rede USB: LIGADA (IP inválido)"
            T_LINE_OFF="Rede USB: \Z1DESLIGADA\Zn"
            T_SSH="Execute no CMD: ssh ark@%s - Senha: ark"
            T_SELECT="Selecione:"
            T_NO_CONN="Sem conexão"
            T_NET_OK_STATUS="OK (acesso à Internet)"
            T_FAILED="FALHOU"
            T_MENU_WIN="Instruções para Windows"
            ;;
        es)
            T_DEPS="Error fatal: dependencia '%s' no encontrada."
            T_DEACTIVATING="Desactivando red USB...\nEspere."
            T_OTHER_MODE="Red USB de otro modo activa.\n\n¿Desactivarla?"
            T_ACTIVATING="Activando red USB (Internet + SSH)...\nEspere."
            T_ERR_CREATE="Error: no se pudo crear %s\n\nVer %s"
            T_ERR_FUNC="Error: ninguna funcion USB disponible.\n\nVer %s"
            T_ERR_UDC="Error: fallo al activar UDC '%s'.\n\nVer %s"
            T_ERR_IFACE="Error: la interfaz USB no aparecio.\n\nVer %s"
            T_ERR_IP="Error al aplicar IP.\n\nVer %s"
            T_NET_ON="Red USB ACTIVADA.\n\nInterfaz: %s\nIP: %s\n\nLog: %s"
            T_AUTOSTART_OFF="Inicio automatico DESACTIVADO."
            T_AUTOSTART_ON="Inicio automatico ACTIVADO.\n\nServicio: darkos-usbnet.service\nModo: g_ether (boot)\nScript: %s"
            T_STATUS_ACTIVE_INT="Red USB ACTIVA\n\nInternet: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="Red USB ACTIVA\nIP no configurado."
            T_STATUS_OFF="Red USB \Z1DESACTIVADA\Zn."
            T_INSTRUCTIONS="=== INSTRUCCIONES PARA WINDOWS ===\n\n\Z11.\Zn Conecte el R36S via USB.\n\Z12.\Zn Panel de Control > Red > Conexiones de Red.\n\Z13.\Zn Clic en el adaptador con Internet.\n\Z14.\Zn Propiedades > Compartir > marcar.\n\Z15.\Zn Seleccione 'Remote NDIS based Internet Sharing'."
            T_IP_UPDATED="IP actualizado a %s."
            T_IP_SAVED="IP guardado: %s."
            T_IP_MENU="Elija IP (192.168.137.X)\n\nPuerta de enlace: %s"
            T_MENU_OFF="Desactivar Red USB"
            T_MENU_ON="Activar Red USB (Internet + SSH)"
            T_VERIFY="Verificar Estado"
            T_CHANGE_IP="Cambiar IP Fija"
            T_AUTO_ON_LABEL="Activar Inicio Automatico"
            T_AUTO_OFF_LABEL="Desactivar Inicio Automatico"
            T_EXIT_KEEP="Salir (red sigue activa)"
            T_EXIT="Salir"
            T_TITLE="Gestor de Red USB v0.5"
            T_EMPTY="El menu devolvio vacio.\nEsto suele pasar en el primer clic.\n\n¿Intentar de nuevo?"
            T_CONFIRM_OFF="Esto desconectara la red USB.\n\n¿Continuar?"
            T_KEEP_ACTIVE="La red USB sigue activa.\nEjecute de nuevo para gestionar."
            T_NET_OK="Estado: OK"
            T_NET_NO="Estado: \Z1SIN CONEXION\Zn"
            T_NET_UNAVAIL="Estado: NO DISPONIBLE"
            T_NET_OFF="Estado: \Z1DESACTIVADA\Zn"
            T_LINE_ON="Red USB: ON | IP: %s"
            T_LINE_ON_NOIP="Red USB: ON (IP invalida)"
            T_LINE_OFF="Red USB: \Z1OFF\Zn"
            T_SSH="Ejecute en CMD: ssh ark@%s - Contraseña: ark"
            T_SELECT="Seleccione:"
            T_NO_CONN="Sin conexion"
            T_NET_OK_STATUS="OK (acceso a Internet)"
            T_FAILED="FALLO"
            T_MENU_WIN="Instrucciones para Windows"
            ;;
        zh)
            T_DEPS="致命错误：未找到依赖 '%s'。"
            T_DEACTIVATING="正在禁用USB网络...\n请稍候。"
            T_OTHER_MODE="另一个模式的USB网络已激活。\n\n是否禁用？"
            T_ACTIVATING="正在启用USB网络（互联网 + SSH）...\n请稍候。"
            T_ERR_CREATE="错误：无法创建 %s\n\n查看 %s"
            T_ERR_FUNC="错误：没有可用的USB功能。\n\n查看 %s"
            T_ERR_UDC="错误：激活UDC '%s' 失败。\n\n查看 %s"
            T_ERR_IFACE="错误：USB接口未出现。\n\n查看 %s"
            T_ERR_IP="应用IP时出错。\n\n查看 %s"
            T_NET_ON="USB网络已启用。\n\n接口: %s\nIP: %s\n\n日志: %s"
            T_AUTOSTART_OFF="自动启动已禁用。"
            T_AUTOSTART_ON="自动启动已启用。\n\n服务: darkos-usbnet.service\n模式: g_ether (boot)\n脚本: %s"
            T_STATUS_ACTIVE_INT="USB网络已激活\n\n互联网: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="USB网络已激活\nIP未配置。"
            T_STATUS_OFF="USB网络 \Z1已禁用\Zn。"
            T_INSTRUCTIONS="=== WINDOWS 说明 ===\n\n\Z11.\Zn 通过USB连接R36S。\n\Z12.\Zn 控制面板 > 网络 > 网络连接。\n\Z13.\Zn 点击有互联网的适配器。\n\Z14.\Zn 属性 > 共享 > 勾选。\n\Z15.\Zn 选择 'Remote NDIS based Internet Sharing'。"
            T_IP_UPDATED="IP已更新为 %s。"
            T_IP_SAVED="IP已保存: %s。"
            T_IP_MENU="选择IP (192.168.137.X)\n\n网关: %s"
            T_MENU_OFF="禁用USB网络"
            T_MENU_ON="启用USB网络（互联网 + SSH）"
            T_VERIFY="检查状态"
            T_CHANGE_IP="更改固定IP"
            T_AUTO_ON_LABEL="启用自动启动"
            T_AUTO_OFF_LABEL="禁用自动启动"
            T_EXIT_KEEP="退出（网络保持激活）"
            T_EXIT="退出"
            T_TITLE="USB网络管理器 v0.5"
            T_EMPTY="菜单返回空。\n这通常发生在第一次点击时。\n\n再试一次？"
            T_CONFIRM_OFF="这将断开USB网络。\n\n继续？"
            T_KEEP_ACTIVE="USB网络保持激活。\n再次运行以管理。"
            T_NET_OK="状态: OK"
            T_NET_NO="状态: \Z1无连接\Zn"
            T_NET_UNAVAIL="状态: 不可用"
            T_NET_OFF="状态: \Z1已禁用\Zn"
            T_LINE_ON="USB网络: 开 | IP: %s"
            T_LINE_ON_NOIP="USB网络: 开（IP无效）"
            T_LINE_OFF="USB网络: \Z1关\Zn"
            T_SSH="在CMD中运行: ssh ark@%s - 密码: ark"
            T_SELECT="选择:"
            T_NO_CONN="无连接"
            T_NET_OK_STATUS="OK（可访问互联网）"
            T_FAILED="失败"
            T_MENU_WIN="Windows 说明"
            ;;
        ja)
            T_DEPS="致命的エラー：依存関係 '%s' が見つかりません。"
            T_DEACTIVATING="USBネットワークを無効化中...\nお待ちください。"
            T_OTHER_MODE="別のモードのUSBネットワークが有効です。\n\n無効にしますか？"
            T_ACTIVATING="USBネットワークを有効化中（インターネット + SSH）...\nお待ちください。"
            T_ERR_CREATE="エラー：%s を作成できませんでした\n\n%s を参照"
            T_ERR_FUNC="エラー：利用可能なUSB機能がありません。\n\n%s を参照"
            T_ERR_UDC="エラー：UDC '%s' の有効化に失敗しました。\n\n%s を参照"
            T_ERR_IFACE="エラー：USBインターフェースが表示されませんでした。\n\n%s を参照"
            T_ERR_IP="IPの適用中にエラー。\n\n%s を参照"
            T_NET_ON="USBネットワーク有効。\n\nインターフェース: %s\nIP: %s\n\nログ: %s"
            T_AUTOSTART_OFF="自動起動が無効になりました。"
            T_AUTOSTART_ON="自動起動が有効になりました。\n\nサービス: darkos-usbnet.service\nモード: g_ether (boot)\nスクリプト: %s"
            T_STATUS_ACTIVE_INT="USBネットワーク有効\n\nインターネット: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="USBネットワーク有効\nIP未設定。"
            T_STATUS_OFF="USBネットワーク \Z1無効\Zn。"
            T_INSTRUCTIONS="=== WINDOWS 手順 ===\n\n\Z11.\Zn R36SをUSBで接続。\n\Z12.\Zn コントロールパネル > ネットワーク > ネットワーク接続。\n\Z13.\Zn インターネットのあるアダプターをクリック。\n\Z14.\Zn プロパティ > 共有 > チェック。\n\Z15.\Zn 'Remote NDIS based Internet Sharing' を選択。"
            T_IP_UPDATED="IPを %s に更新しました。"
            T_IP_SAVED="IP保存済み: %s。"
            T_IP_MENU="IPを選択 (192.168.137.X)\n\nゲートウェイ: %s"
            T_MENU_OFF="USBネットワークを無効化"
            T_MENU_ON="USBネットワークを有効化（インターネット + SSH）"
            T_VERIFY="ステータス確認"
            T_CHANGE_IP="固定IPを変更"
            T_AUTO_ON_LABEL="自動起動を有効化"
            T_AUTO_OFF_LABEL="自動起動を無効化"
            T_EXIT_KEEP="終了（ネットワークは有効のまま）"
            T_EXIT="終了"
            T_TITLE="USBネットワークマネージャー v0.5"
            T_EMPTY="メニューが空を返しました。\nこれは最初のクリックでよく発生します。\n\n再試行しますか？"
            T_CONFIRM_OFF="USBネットワークが切断されます。\n\n続行しますか？"
            T_KEEP_ACTIVE="USBネットワークは有効のままです。\n再度実行して管理してください。"
            T_NET_OK="ステータス: OK"
            T_NET_NO="ステータス: \Z1接続なし\Zn"
            T_NET_UNAVAIL="ステータス: 利用不可"
            T_NET_OFF="ステータス: \Z1無効\Zn"
            T_LINE_ON="USBネットワーク: オン | IP: %s"
            T_LINE_ON_NOIP="USBネットワーク: オン（IP無効）"
            T_LINE_OFF="USBネットワーク: \Z1オフ\Zn"
            T_SSH="CMDで実行: ssh ark@%s - パスワード: ark"
            T_SELECT="選択:"
            T_NO_CONN="接続なし"
            T_NET_OK_STATUS="OK（インターネット接続）"
            T_FAILED="失敗"
            T_MENU_WIN="Windows 手順"
            ;;
        it)
            T_DEPS="Errore fatale: dipendenza '%s' non trovata."
            T_DEACTIVATING="Disattivazione rete USB...\nAttendere."
            T_OTHER_MODE="Rete USB di un'altra modalità attiva.\n\nDisattivarla?"
            T_ACTIVATING="Attivazione rete USB (Internet + SSH)...\nAttendere."
            T_ERR_CREATE="Errore: impossibile creare %s\n\nVedi %s"
            T_ERR_FUNC="Errore: nessuna funzione USB disponibile.\n\nVedi %s"
            T_ERR_UDC="Errore: attivazione UDC '%s' fallita.\n\nVedi %s"
            T_ERR_IFACE="Errore: l'interfaccia USB non è apparsa.\n\nVedi %s"
            T_ERR_IP="Errore nell'applicazione dell'IP.\n\nVedi %s"
            T_NET_ON="Rete USB ATTIVATA.\n\nInterfaccia: %s\nIP: %s\n\nLog: %s"
            T_AUTOSTART_OFF="Avvio automatico DISATTIVATO."
            T_AUTOSTART_ON="Avvio automatico ATTIVATO.\n\nServizio: darkos-usbnet.service\nModalità: g_ether (boot)\nScript: %s"
            T_STATUS_ACTIVE_INT="Rete USB ATTIVA\n\nInternet: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="Rete USB ATTIVA\nIP non configurato."
            T_STATUS_OFF="Rete USB \Z1DISATTIVATA\Zn."
            T_INSTRUCTIONS="=== ISTRUZIONI PER WINDOWS ===\n\n\Z11.\Zn Collegare R36S via USB.\n\Z12.\Zn Pannello di Controllo > Rete > Connessioni di Rete.\n\Z13.\Zn Cliccare sull'adattatore con Internet.\n\Z14.\Zn Proprietà > Condivisione > selezionare.\n\Z15.\Zn Selezionare 'Remote NDIS based Internet Sharing'."
            T_IP_UPDATED="IP aggiornato a %s."
            T_IP_SAVED="IP salvato: %s."
            T_IP_MENU="Scegli IP (192.168.137.X)\n\nGateway: %s"
            T_MENU_OFF="Disattiva Rete USB"
            T_MENU_ON="Attiva Rete USB (Internet + SSH)"
            T_VERIFY="Verifica Stato"
            T_CHANGE_IP="Cambia IP Statico"
            T_AUTO_ON_LABEL="Attiva Avvio Automatico"
            T_AUTO_OFF_LABEL="Disattiva Avvio Automatico"
            T_EXIT_KEEP="Esci (rete resta attiva)"
            T_EXIT="Esci"
            T_TITLE="Gestore Rete USB v0.5"
            T_EMPTY="Il menu ha restituito vuoto.\nQuesto succede spesso al primo clic.\n\nRiprovare?"
            T_CONFIRM_OFF="Questo disconnetterà la rete USB.\n\nContinuare?"
            T_KEEP_ACTIVE="La rete USB resta attiva.\nEseguire di nuovo per gestire."
            T_NET_OK="Stato: OK"
            T_NET_NO="Stato: \Z1NESSUNA CONNESSIONE\Zn"
            T_NET_UNAVAIL="Stato: NON DISPONIBILE"
            T_NET_OFF="Stato: \Z1DISATTIVATA\Zn"
            T_LINE_ON="Rete USB: ON | IP: %s"
            T_LINE_ON_NOIP="Rete USB: ON (IP non valido)"
            T_LINE_OFF="Rete USB: \Z1OFF\Zn"
            T_SSH="Esegui in CMD: ssh ark@%s - Password: ark"
            T_SELECT="Seleziona:"
            T_NO_CONN="Nessuna connessione"
            T_NET_OK_STATUS="OK (accesso a Internet)"
            T_FAILED="FALLITO"
            T_MENU_WIN="Istruzioni per Windows"
            ;;
        ru)
            T_DEPS="Критическая ошибка: зависимость '%s' не найдена."
            T_DEACTIVATING="Отключение USB-сети...\nПодождите."
            T_OTHER_MODE="USB-сеть другого режима активна.\n\nОтключить её?"
            T_ACTIVATING="Включение USB-сети (Интернет + SSH)...\nПодождите."
            T_ERR_CREATE="Ошибка: не удалось создать %s\n\nСм. %s"
            T_ERR_FUNC="Ошибка: нет доступной USB-функции.\n\nСм. %s"
            T_ERR_UDC="Ошибка: не удалось активировать UDC '%s'.\n\nСм. %s"
            T_ERR_IFACE="Ошибка: USB-интерфейс не появился.\n\nСм. %s"
            T_ERR_IP="Ошибка при применении IP.\n\nСм. %s"
            T_NET_ON="USB-сеть ВКЛЮЧЕНА.\n\nИнтерфейс: %s\nIP: %s\n\nЛог: %s"
            T_AUTOSTART_OFF="Автозапуск ОТКЛЮЧЕН."
            T_AUTOSTART_ON="Автозапуск ВКЛЮЧЕН.\n\nСлужба: darkos-usbnet.service\nРежим: g_ether (boot)\nСкрипт: %s"
            T_STATUS_ACTIVE_INT="USB-сеть АКТИВНА\n\nИнтернет: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="USB-сеть АКТИВНА\nIP не настроен."
            T_STATUS_OFF="USB-сеть \Z1ОТКЛЮЧЕНА\Zn."
            T_INSTRUCTIONS="=== ИНСТРУКЦИЯ ДЛЯ WINDOWS ===\n\n\Z11.\Zn Подключите R36S через USB.\n\Z12.\Zn Панель управления > Сеть > Сетевые подключения.\n\Z13.\Zn Нажмите на адаптер с Интернетом.\n\Z14.\Zn Свойства > Доступ > включить.\n\Z15.\Zn Выберите 'Remote NDIS based Internet Sharing'."
            T_IP_UPDATED="IP обновлён на %s."
            T_IP_SAVED="IP сохранён: %s."
            T_IP_MENU="Выберите IP (192.168.137.X)\n\nШлюз: %s"
            T_MENU_OFF="Отключить USB-сеть"
            T_MENU_ON="Включить USB-сеть (Интернет + SSH)"
            T_VERIFY="Проверить статус"
            T_CHANGE_IP="Изменить статический IP"
            T_AUTO_ON_LABEL="Включить автозапуск"
            T_AUTO_OFF_LABEL="Отключить автозапуск"
            T_EXIT_KEEP="Выход (сеть остаётся активной)"
            T_EXIT="Выход"
            T_TITLE="Менеджер USB-сети v0.5"
            T_EMPTY="Меню вернуло пусто.\nОбычно это происходит при первом клике.\n\nПопробовать снова?"
            T_CONFIRM_OFF="Это отключит USB-сеть.\n\nПродолжить?"
            T_KEEP_ACTIVE="USB-сеть остаётся активной.\nЗапустите снова для управления."
            T_NET_OK="Статус: OK"
            T_NET_NO="Статус: \Z1НЕТ СОЕДИНЕНИЯ\Zn"
            T_NET_UNAVAIL="Статус: НЕДОСТУПНО"
            T_NET_OFF="Статус: \Z1ОТКЛЮЧЕНА\Zn"
            T_LINE_ON="USB-сеть: ВКЛ | IP: %s"
            T_LINE_ON_NOIP="USB-сеть: ВКЛ (неверный IP)"
            T_LINE_OFF="USB-сеть: \Z1ВЫКЛ\Zn"
            T_SSH="Выполните в CMD: ssh ark@%s - Пароль: ark"
            T_SELECT="Выберите:"
            T_NO_CONN="Нет соединения"
            T_NET_OK_STATUS="OK (доступ в Интернет)"
            T_FAILED="СБОЙ"
            T_MENU_WIN="Инструкция для Windows"
            ;;
        *)
            LANG_ID="en"
            T_DEPS="Fatal error: dependency '%s' not found."
            T_DEACTIVATING="Disabling USB network...\nPlease wait."
            T_OTHER_MODE="USB network from another mode is active.\n\nDisable it?"
            T_ACTIVATING="Enabling USB network (Internet + SSH)...\nPlease wait."
            T_ERR_CREATE="Error: could not create %s\n\nSee %s"
            T_ERR_FUNC="Error: no USB function available.\n\nSee %s"
            T_ERR_UDC="Error: failed to activate UDC '%s'.\n\nSee %s"
            T_ERR_IFACE="Error: USB interface did not appear.\n\nSee %s"
            T_ERR_IP="Error applying IP.\n\nSee %s"
            T_NET_ON="USB network ENABLED.\n\nInterface: %s\nIP: %s\n\nLog: %s"
            T_AUTOSTART_OFF="Autostart DISABLED."
            T_AUTOSTART_ON="Autostart ENABLED.\n\nService: darkos-usbnet.service\nMode: g_ether (boot)\nScript: %s"
            T_STATUS_ACTIVE_INT="USB network ACTIVE\n\nInternet: %s\nIP: %s\nSSH: ssh ark@%s"
            T_STATUS_ACTIVE_NOIP="USB network ACTIVE\nIP not configured."
            T_STATUS_OFF="USB network \Z1DISABLED\Zn."
            T_INSTRUCTIONS="=== WINDOWS INSTRUCTIONS ===\n\n\Z11.\Zn Connect R36S via USB.\n\Z12.\Zn Control Panel > Network > Network Connections.\n\Z13.\Zn Click the adapter with Internet.\n\Z14.\Zn Properties > Sharing > check.\n\Z15.\Zn Select 'Remote NDIS based Internet Sharing'."
            T_IP_UPDATED="IP updated to %s."
            T_IP_SAVED="IP saved: %s."
            T_IP_MENU="Choose IP (192.168.137.X)\n\nGateway: %s"
            T_MENU_OFF="Disable USB Network"
            T_MENU_ON="Enable USB Network (Internet + SSH)"
            T_VERIFY="Check Status"
            T_CHANGE_IP="Change Static IP"
            T_AUTO_ON_LABEL="Enable Autostart"
            T_AUTO_OFF_LABEL="Disable Autostart"
            T_EXIT_KEEP="Exit (network stays active)"
            T_EXIT="Exit"
            T_TITLE="USB Network Manager v0.5"
            T_EMPTY="Menu returned empty.\nThis usually happens on the first click.\n\nTry again?"
            T_CONFIRM_OFF="This will bring down the USB network.\n\nContinue?"
            T_KEEP_ACTIVE="USB network remains active.\nRun again to manage."
            T_NET_OK="Status: OK"
            T_NET_NO="Status: \Z1NO CONNECTION\Zn"
            T_NET_UNAVAIL="Status: UNAVAILABLE"
            T_NET_OFF="Status: \Z1DISABLED\Zn"
            T_LINE_ON="USB network: ON | IP: %s"
            T_LINE_ON_NOIP="USB network: ON (invalid IP)"
            T_LINE_OFF="USB network: \Z1OFF\Zn"
            T_SSH="Run in CMD: ssh ark@%s - Password: ark"
            T_SELECT="Select:"
            T_NO_CONN="No connection"
            T_NET_OK_STATUS="OK (Internet access)"
            T_FAILED="FAILED"
            T_MENU_WIN="Windows Instructions"
            ;;
    esac
}

width="58"
height="18"

if [ "$1" != "--internet" ]; then
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25l" > "$CURR_TTY"
    export TERM=linux
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR

    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null
        width="58"
        height="18"
    else
        setfont /usr/share/consolefonts/Lat15-TerminusBold24x12.psf.gz 2>/dev/null
        width="50"
        height="16"
    fi

    pkill -9 -f "gptokeyb -1 $SCRIPT_NAME" || true
    pkill -9 -f osk.py || true
    sleep 1
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release 2>/dev/null || true
    FIRMWARE_ID="${ID:-unknown}"
fi

DetectLanguage
SetLanguage

for svc in usbinet.service usbssh.service usb-gadget.service otg.service; do
    systemctl disable "$svc" 2>/dev/null || true
    systemctl stop "$svc" 2>/dev/null || true
done

for dep in dialog ip; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        printf "$T_DEPS\n" "$dep" > "$CURR_TTY"
        sleep 3
        exit 1
    fi
done

PrepareCustomKeys() {
    if [ -f "$SYSTEM_KEYS_FILE" ]; then
        sed -e 's/^[[:space:]]*a[[:space:]]*=.*/a = enter/' \
            -e 's/^[[:space:]]*b[[:space:]]*=.*/b = esc/' \
            "$SYSTEM_KEYS_FILE" > "$CUSTOM_KEYS_FILE" 2>/dev/null || true
    fi

    if [ ! -s "$CUSTOM_KEYS_FILE" ]; then
        cat > "$CUSTOM_KEYS_FILE" <<'EOF'
back = esc
start = enter
a = enter
b = esc
x = \"
y = \"
l1 = pageup
l2 = \"
l3 = \"
r1 = pagedown
r2 = \"
r3 = \"
up = up
down = down
left = left
right = right
left_analog_up = up
left_analog_down = down
left_analog_left = left
left_analog_right = right
right_analog_up = \"
right_analog_down = \"
right_analog_left = \"
right_analog_right = \"
EOF
    fi
}

RestoreConsole() {
    printf "\033c" > "$CURR_TTY"
    printf "\e[?25h" > "$CURR_TTY"
    pkill -f "gptokeyb -1 $SCRIPT_NAME" || true
    if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
        setfont /usr/share/consolefonts/Lat15-TerminusBold20x10.psf.gz 2>/dev/null
    fi
}

GetStaticOctet() {
    [ -f "$STATIC_OCTET_FILE" ] && cat "$STATIC_OCTET_FILE" || echo "$DEFAULT_OCTET"
}

SetStaticOctet() {
    mkdir -p "$(dirname "$STATIC_OCTET_FILE")" 2>/dev/null
    echo "$1" > "$STATIC_OCTET_FILE"
}

ApplyStaticDNS() {
    LOG "DNS: aplicando (DNS_APPLIED=$DNS_APPLIED)"
    if [ "$DNS_APPLIED" -eq 0 ]; then
        if [ -L "$RESOLV_CONF" ]; then
            readlink "$RESOLV_CONF" > "$RESOLV_SYMLINK_FILE" 2>/dev/null || true
        elif [ -f "$RESOLV_CONF" ] && [ ! -f "$RESOLV_BACKUP_FILE" ]; then
            cp "$RESOLV_CONF" "$RESOLV_BACKUP_FILE" 2>/dev/null || true
        fi
    fi
    [ -L "$RESOLV_CONF" ] && rm -f "$RESOLV_CONF" 2>/dev/null || true
    if {
        echo "# Gerenciado pelo R36S USB Network"
        echo "nameserver $STATIC_GATEWAY"
        echo "nameserver 1.1.1.1"
    } > "$RESOLV_CONF" 2>/dev/null; then
        DNS_APPLIED=1
    fi
}

RestoreDNS() {
    [ "$DNS_APPLIED" -eq 0 ] && return 0
    if [ -f "$RESOLV_SYMLINK_FILE" ]; then
        rm -f "$RESOLV_CONF" 2>/dev/null || true
        ln -s "$(cat "$RESOLV_SYMLINK_FILE")" "$RESOLV_CONF" 2>/dev/null || true
        rm -f "$RESOLV_SYMLINK_FILE" 2>/dev/null || true
    elif [ -f "$RESOLV_BACKUP_FILE" ]; then
        cp "$RESOLV_BACKUP_FILE" "$RESOLV_CONF" 2>/dev/null || true
        rm -f "$RESOLV_BACKUP_FILE" 2>/dev/null || true
    fi
    DNS_APPLIED=0
}

RemoveGadget() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    LOG "RemoveGadget: $dir"
    echo "" > "$dir/UDC" 2>/dev/null || true
    rm -f "$dir/configs/c.1/rndis.usb0" "$dir/configs/c.1/ecm.usb0" "$dir/configs/c.1/ncm.usb0" 2>/dev/null || true
    rmdir "$dir/configs/c.1/strings/0x409" "$dir/configs/c.1" 2>/dev/null || true
    rmdir "$dir/functions/rndis.usb0" "$dir/functions/ecm.usb0" "$dir/functions/ncm.usb0" 2>/dev/null || true
    rmdir "$dir/strings/0x409" "$dir" 2>/dev/null || true
}

CleanupGadget() {
    local mode=$1
    LOG "CleanupGadget: mode=$mode"
    [ "$mode" != "silent" ] && dialog --colors --infobox "$T_DEACTIVATING" 5 $width > "$CURR_TTY"
    [ -n "$SSHD_PID" ] && { kill "$SSHD_PID" 2>/dev/null || true; SSHD_PID=""; }
    RemoveGadget "$GADGET_DIR"
    rmmod g_ether 2>/dev/null || true
    RestoreDNS
    sleep 1
}

CheckConflictingGadget() {
    local boot_mode="$1"
    if [ -d "$OTHER_GADGET_DIR" ]; then
        if [ "$boot_mode" == "boot" ]; then
            RemoveGadget "$OTHER_GADGET_DIR"
            return 0
        fi
        if dialog --colors --yesno "$T_OTHER_MODE" 8 $width > "$CURR_TTY"; then
            RemoveGadget "$OTHER_GADGET_DIR"
            return 0
        fi
        return 1
    fi
    return 0
}

SnapshotInterfaces() {
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | sort
}

FindNewInterface() {
    local before="$1" after
    after=$(SnapshotInterfaces)
    comm -13 <(echo "$before") <(echo "$after") 2>/dev/null | grep -v '@' | head -1
}

DetectActiveInterface() {
    [ -n "$INTERFACE_NAME" ] && ip link show "$INTERFACE_NAME" >/dev/null 2>&1 && return 0
    local c
    for c in usb0 usb1 usb2; do
        ip link show "$c" >/dev/null 2>&1 && { INTERFACE_NAME="$c"; return 0; }
    done
    local p n
    for p in /sys/class/net/*; do
        n=$(basename "$p")
        case "$n" in
            usb*|enx*|enp*u*) INTERFACE_NAME="$n"; return 0 ;;
        esac
    done
    return 1
}

ApplyStaticIP() {
    local octet
    octet=$(GetStaticOctet)
    LOG "ApplyStaticIP: ${STATIC_NETWORK}.${octet}/${STATIC_PREFIX} em $INTERFACE_NAME"
    ip addr flush dev "$INTERFACE_NAME" 2>/dev/null || true
    if ! ip addr add "${STATIC_NETWORK}.${octet}/${STATIC_PREFIX}" dev "$INTERFACE_NAME" 2>>"$LOG_FILE"; then
        LOG "ApplyStaticIP: falha ao adicionar IP"
        return 1
    fi
    ip link set "$INTERFACE_NAME" up
    ip route replace default via "$STATIC_GATEWAY" dev "$INTERFACE_NAME" 2>>"$LOG_FILE" || \
        LOG "ApplyStaticIP: aviso - falha ao definir rota default"
    ApplyStaticDNS
    return 0
}

StartNetworkBoot() {
    LOG "===== StartNetworkBoot (g_ether) ====="
    RotateLogIfNeeded

    CheckConflictingGadget "boot"
    CleanupGadget "silent"

    local dev_mac="42:61:72:6b:6f:53"
    local host_mac="42:61:72:6b:6f:54"
    local interfaces_before
    interfaces_before=$(SnapshotInterfaces)

    local tries=0 loaded=0
    while [ $tries -lt 10 ]; do
        if modprobe g_ether dev_addr="$dev_mac" host_addr="$host_mac" 2>>"$LOG_FILE"; then
            loaded=1
            break
        fi
        tries=$((tries+1))
        LOG "g_ether falhou (tentativa $tries/10)"
        sleep 3
    done

    if [ $loaded -eq 0 ]; then
        LOG "falha ao carregar g_ether"
        return 1
    fi

    local waited=0
    INTERFACE_NAME=""
    while [ -z "$INTERFACE_NAME" ] && [ $waited -lt 20 ]; do
        if [ -e /sys/class/net/usb0 ]; then
            INTERFACE_NAME="usb0"
        else
            INTERFACE_NAME=$(FindNewInterface "$interfaces_before")
        fi
        [ -z "$INTERFACE_NAME" ] && sleep 1
        waited=$((waited+1))
    done

    if [ -z "$INTERFACE_NAME" ]; then
        LOG "interface USB nao apareceu apos 20s"
        return 1
    fi

    LOG "Interface $INTERFACE_NAME pronta"

    ip link set "$INTERFACE_NAME" up
    if ! ApplyStaticIP; then
        LOG "falha ao aplicar IP estatico"
        return 1
    fi

    if ! pgrep -x "sshd" >/dev/null; then
        if systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null; then
            LOG "sshd via systemd"
        elif [ -x /usr/sbin/sshd ]; then
            /usr/sbin/sshd -D >>"$LOG_FILE" 2>&1 &
            SSHD_PID=$!
            LOG "sshd ad-hoc PID=$SSHD_PID"
        else
            LOG "sshd nao encontrado"
        fi
    fi

    LOG "===== StartNetworkBoot FIM ====="
    return 0
}

StartNetworkInteractive() {
    LOG "===== StartNetworkInteractive (libcomposite) ====="
    RotateLogIfNeeded

    if ! CheckConflictingGadget "interactive"; then
        LOG "StartNetworkInteractive: abortado"
        return 1
    fi

    dialog --colors --infobox "$T_ACTIVATING" 5 $width > "$CURR_TTY"

    CleanupGadget "silent"

    local interfaces_before
    interfaces_before=$(SnapshotInterfaces)

    modprobe libcomposite 2>>"$LOG_FILE" || LOG "libcomposite falhou"
    modprobe usb_f_rndis  2>>"$LOG_FILE" || LOG "rndis falhou"
    modprobe usb_f_ecm    2>>"$LOG_FILE" || LOG "ecm falhou"
    modprobe usb_f_ncm    2>>"$LOG_FILE" || LOG "ncm falhou"
    sleep 2

    local udc_device="" udc
    for udc in /sys/class/udc/*; do
        [ -e "$udc" ] && { udc_device=$(basename "$udc"); break; }
    done
    [ -z "$udc_device" ] && udc_device="ff300000.usb"
    LOG "UDC: $udc_device"

    if ! mkdir -p "$GADGET_DIR/strings/0x409" "$GADGET_DIR/configs/c.1/strings/0x409" 2>>"$LOG_FILE"; then
        LOG "falha ao criar $GADGET_DIR"
        dialog --colors --msgbox "$(printf "$T_ERR_CREATE" "$GADGET_DIR" "$LOG_FILE")" 8 $width > "$CURR_TTY"
        return 1
    fi

    echo 0x1d6b > "$GADGET_DIR/idVendor"
    echo 0x0104 > "$GADGET_DIR/idProduct"
    echo "DARKOS_R36S_NET" > "$GADGET_DIR/strings/0x409/serialnumber"
    echo "dArkOS Team" > "$GADGET_DIR/strings/0x409/manufacturer"
    echo "dArkOS Gaming Console" > "$GADGET_DIR/strings/0x409/product"
    echo "USB Network (Internet+SSH)" > "$GADGET_DIR/configs/c.1/strings/0x409/configuration"
    echo 500 > "$GADGET_DIR/configs/c.1/MaxPower"

    local func_used=""
    if mkdir -p "$GADGET_DIR/functions/rndis.usb0" 2>>"$LOG_FILE"; then
        ln -sf "$GADGET_DIR/functions/rndis.usb0" "$GADGET_DIR/configs/c.1/"
        func_used="rndis"
    elif mkdir -p "$GADGET_DIR/functions/ecm.usb0" 2>>"$LOG_FILE"; then
        ln -sf "$GADGET_DIR/functions/ecm.usb0" "$GADGET_DIR/configs/c.1/"
        func_used="ecm"
    elif mkdir -p "$GADGET_DIR/functions/ncm.usb0" 2>>"$LOG_FILE"; then
        ln -sf "$GADGET_DIR/functions/ncm.usb0" "$GADGET_DIR/configs/c.1/"
        func_used="ncm"
    else
        LOG "nem rndis, ecm ou ncm disponiveis"
        dialog --colors --msgbox "$(printf "$T_ERR_FUNC" "$LOG_FILE")" 8 $width > "$CURR_TTY"
        RemoveGadget "$GADGET_DIR"
        return 1
    fi
    LOG "Funcao USB: $func_used"

    if ! echo "$udc_device" > "$GADGET_DIR/UDC" 2>>"$LOG_FILE"; then
        LOG "falha ao escrever UDC $udc_device"
        dialog --colors --msgbox "$(printf "$T_ERR_UDC" "$udc_device" "$LOG_FILE")" 9 $width > "$CURR_TTY"
        RemoveGadget "$GADGET_DIR"
        return 1
    fi
    sleep 3

    local retries=0
    INTERFACE_NAME=""
    while [ -z "$INTERFACE_NAME" ] && [ $retries -lt 15 ]; do
        INTERFACE_NAME=$(FindNewInterface "$interfaces_before")
        [ -z "$INTERFACE_NAME" ] && sleep 1
        ((retries++))
    done
    if [ -z "$INTERFACE_NAME" ]; then
        for c in usb0 usb1 usb2; do
            ip link show "$c" >/dev/null 2>&1 && { INTERFACE_NAME="$c"; break; }
        done
    fi
    LOG "Interface: ${INTERFACE_NAME:-NENHUMA}"

    if [ -z "$INTERFACE_NAME" ]; then
        dialog --colors --msgbox "$(printf "$T_ERR_IFACE" "$LOG_FILE")" 7 $width > "$CURR_TTY"
        RemoveGadget "$GADGET_DIR"
        return 1
    fi

    ip link set "$INTERFACE_NAME" up 2>>"$LOG_FILE"
    if ! ApplyStaticIP; then
        dialog --colors --msgbox "$(printf "$T_ERR_IP" "$LOG_FILE")" 7 $width > "$CURR_TTY"
    fi
    sleep 1

    local current_ip
    current_ip=$(ip -4 addr show "$INTERFACE_NAME" | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    LOG "IP final: ${current_ip:-nenhum}"

    if ! pgrep -x "sshd" >/dev/null; then
        if systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null; then
            LOG "sshd via systemd"
        elif [ -x /usr/sbin/sshd ]; then
            /usr/sbin/sshd -D >>"$LOG_FILE" 2>&1 &
            SSHD_PID=$!
            LOG "sshd ad-hoc PID=$SSHD_PID"
        else
            LOG "sshd nao encontrado"
        fi
    fi

    sleep 1
    LOG "===== StartNetworkInteractive FIM ====="

    dialog --colors --msgbox "$(printf "$T_NET_ON" "$INTERFACE_NAME" "${current_ip:-$T_FAILED}" "$LOG_FILE")" 9 $width > "$CURR_TTY"
}

InstallService() {
    mkdir -p /opt/system
    echo "--internet" > "$AUTOSTART_FILE"
    cat > /etc/systemd/system/darkos-usbnet.service <<EOF
[Unit]
Description=R36S USB Network Service (g_ether)
After=local-fs.target systemd-modules-load.service network.target
RequiresMountsFor=$(dirname "$SCRIPT_FULL_PATH")

[Service]
Type=simple
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/bin/bash "$SCRIPT_FULL_PATH" --internet
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null
    systemctl enable darkos-usbnet.service 2>/dev/null
}

ToggleAutoStart() {
    if [ -f "$AUTOSTART_FILE" ]; then
        rm -f "$AUTOSTART_FILE"
        systemctl disable darkos-usbnet.service 2>/dev/null
        rm -f /etc/systemd/system/darkos-usbnet.service
        systemctl daemon-reload 2>/dev/null
        dialog --colors --msgbox "$T_AUTOSTART_OFF" 5 $width > "$CURR_TTY"
    else
        InstallService
        dialog --colors --msgbox "$(printf "$T_AUTOSTART_ON" "$SCRIPT_FULL_PATH")" 9 $width > "$CURR_TTY"
    fi
}

GetNetworkStatus() {
    IS_ACTIVE=0
    HAS_VALID_IP=0
    HAS_INTERNET=0
    CURRENT_IP="N/A"
    if DetectActiveInterface; then
        IS_ACTIVE=1
        CURRENT_IP=$(ip -4 addr show "$INTERFACE_NAME" | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$CURRENT_IP" ]; then
            HAS_VALID_IP=1
            ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1 && HAS_INTERNET=1 || HAS_INTERNET=0
        fi
    fi
}

CheckStatus() {
    GetNetworkStatus
    if [ $IS_ACTIVE -eq 1 ]; then
        if [ $HAS_VALID_IP -eq 1 ]; then
            local net="$T_NO_CONN"
            [ $HAS_INTERNET -eq 1 ] && net="$T_NET_OK_STATUS"
            dialog --colors --msgbox "$(printf "$T_STATUS_ACTIVE_INT" "$net" "$CURRENT_IP" "$CURRENT_IP")" 9 $width > "$CURR_TTY"
        else
            dialog --colors --msgbox "$T_STATUS_ACTIVE_NOIP" 6 $width > "$CURR_TTY"
        fi
    else
        dialog --colors --msgbox "$T_STATUS_OFF" 5 $width > "$CURR_TTY"
    fi
}

ShowInstructions() {
    dialog --colors --msgbox "$T_INSTRUCTIONS" 15 $width > "$CURR_TTY"
}

ChangeStaticIP() {
    local current_octet new_octet
    current_octet=$(GetStaticOctet)
    local options=() i
    for ((i=254; i>=2; i--)); do
        options+=("$i" "")
    done
    new_octet=$(dialog --colors --default-item "$current_octet" --menu "$(printf "$T_IP_MENU" "$STATIC_GATEWAY")" 14 $width 6 "${options[@]}" 2>&1 >"$CURR_TTY")
    [ -z "$new_octet" ] && return
    SetStaticOctet "$new_octet"
    if [ $IS_ACTIVE -eq 1 ]; then
        ApplyStaticIP
        dialog --colors --msgbox "$(printf "$T_IP_UPDATED" "${STATIC_NETWORK}.${new_octet}")" 6 $width > "$CURR_TTY"
    else
        dialog --colors --msgbox "$(printf "$T_IP_SAVED" "${STATIC_NETWORK}.${new_octet}")" 6 $width > "$CURR_TTY"
    fi
}

LOG "===== Script iniciado (firmware=$FIRMWARE_ID, lang=$LANG_ID, arg='$1') ====="

if [ -e /dev/uinput ]; then
    chmod 666 /dev/uinput 2>/dev/null || true
fi

if [ -f /opt/inttools/gamecontrollerdb.txt ]; then
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
fi

PrepareCustomKeys

if [ "$1" == "--internet" ]; then
    sleep 10
    if StartNetworkBoot; then
        while true; do
            sleep 3600
        done
    else
        exit 1
    fi
fi

if [ -x /opt/inttools/gptokeyb ]; then
    /opt/inttools/gptokeyb -1 "$SCRIPT_NAME" -c "$CUSTOM_KEYS_FILE" > /dev/null 2>&1 &
    sleep 2
fi

if [ -f "$AUTOSTART_FILE" ]; then
    InstallService
fi

trap 'CleanupGadget "silent"; RestoreConsole; exit 0' INT TERM

while true; do
    GetNetworkStatus

    if [ $IS_ACTIVE -eq 1 ]; then
        if [ $HAS_VALID_IP -eq 1 ]; then
            SSH_CMD=$(printf "$T_SSH" "$CURRENT_IP")
            [ $HAS_INTERNET -eq 1 ] && INTERNET_STATUS="$T_NET_OK" || INTERNET_STATUS="$T_NET_NO"
            STATUS_LINE=$(printf "$T_LINE_ON" "$CURRENT_IP")
        else
            SSH_CMD=""
            INTERNET_STATUS="$T_NET_UNAVAIL"
            STATUS_LINE="$T_LINE_ON_NOIP"
        fi
    else
        SSH_CMD=""
        INTERNET_STATUS="$T_NET_OFF"
        STATUS_LINE="$T_LINE_OFF"
    fi

    AUTO_LABEL="$T_AUTO_ON_LABEL"
    [ -f "$AUTOSTART_FILE" ] && AUTO_LABEL="$T_AUTO_OFF_LABEL"

    if [ -n "$SSH_CMD" ]; then
        MENU_TEXT="$INTERNET_STATUS\n$STATUS_LINE\n$SSH_CMD\n\n$T_SELECT"
    else
        MENU_TEXT="$INTERNET_STATUS\n$STATUS_LINE\n\n$T_SELECT"
    fi

    if [ $IS_ACTIVE -eq 1 ]; then
        MENU_ARGS=("1" "$T_MENU_OFF")
        SAIR_LABEL="$T_EXIT_KEEP"
    else
        MENU_ARGS=("1" "$T_MENU_ON")
        SAIR_LABEL="$T_EXIT"
    fi

    MENU_ARGS+=("2" "$T_VERIFY" "3" "$T_CHANGE_IP" "4" "$AUTO_LABEL")
    [ $HAS_INTERNET -eq 0 ] && MENU_ARGS+=("5" "$T_MENU_WIN")
    MENU_ARGS+=("Sair" "$SAIR_LABEL")
    MENU_HEIGHT=$(( ${#MENU_ARGS[@]} / 2 ))

    CHOICE=$(dialog --colors --default-item "1" --backtitle "$APP_NAME" \
        --title "$T_TITLE" \
        --menu "$MENU_TEXT" $height $width "$MENU_HEIGHT" \
        "${MENU_ARGS[@]}" 2>&1 >"$CURR_TTY")
    DIALOG_RC=$?

    if [ -z "$CHOICE" ]; then
        if [ $DIALOG_RC -eq 0 ]; then
            LOG "AVISO: CHOICE vazio com rc=0 - gptokeyb pode nao ter enviado teclas"
            dialog --colors --yesno "$T_EMPTY" 8 $width > "$CURR_TTY" && continue
        fi
        trap - INT TERM
        RestoreConsole
        printf "\033c" > "$CURR_TTY"
        exit 0
    fi

    case "$CHOICE" in
        "1")
            if [ $IS_ACTIVE -eq 1 ]; then
                if dialog --colors --yesno "$T_CONFIRM_OFF" 8 $width > "$CURR_TTY"; then
                    CleanupGadget "verbose"
                fi
            else
                StartNetworkInteractive
            fi
            ;;
        "2")
            CheckStatus
            ;;
        "3")
            ChangeStaticIP
            ;;
        "4")
            ToggleAutoStart
            ;;
        "5")
            ShowInstructions
            ;;
        "Sair")
            trap - INT TERM
            RestoreConsole
            if [ $IS_ACTIVE -eq 1 ]; then
                dialog --colors --infobox "$T_KEEP_ACTIVE" 5 $width > "$CURR_TTY"
                sleep 2
            fi
            printf "\033c" > "$CURR_TTY"
            exit 0
            ;;
        *)
            LOG "CHOICE inesperado: '$CHOICE'"
            ;;
    esac
done