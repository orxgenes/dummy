#!/usr/bin/env bash
# ============================================================
# Setup Arch + VMware + Hyprland + Ghostty (idempotente)
# Ejecutar como usuario normal.
# ============================================================
set -euo pipefail

# ---------- UI helpers ----------
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m-- %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- Validaciones iniciales ----------
[[ $EUID -ne 0 ]]                 || die "Ejecuta como usuario normal, no como root."
command -v pacman &>/dev/null     || die "Este script es solo para Arch Linux."
command -v sudo   &>/dev/null     || die "Necesitas sudo instalado."

if ! systemd-detect-virt 2>/dev/null | grep -q vmware; then
  warn "No detecto VMware ($(systemd-detect-virt 2>/dev/null || echo '?'))."
  read -rp "¿Continuar de todos modos? [y/N] " r
  [[ ${r,,} == "y" ]] || exit 0
fi

# Mantener sudo vivo durante todo el script
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

# ---------- Funciones idempotentes ----------
pkg_install() {
  local missing=()
  for p in "$@"; do
    pacman -Qq "$p" &>/dev/null || missing+=("$p")
  done
  if (( ${#missing[@]} == 0 )); then
    ok "Ya instalados: $*"
  else
    info "Instalando: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
}

svc_enable() {
  local svc=$1
  if systemctl is-enabled --quiet "$svc" 2>/dev/null \
     && systemctl is-active  --quiet "$svc" 2>/dev/null; then
    ok "Servicio activo: $svc"
  else
    info "Habilitando servicio: $svc"
    sudo systemctl enable --now "$svc"
  fi
}

write_file() {
  # write_file <path> <content>
  local path=$1 content=$2
  mkdir -p "$(dirname "$path")"
  if [[ -f $path ]] && [[ $(cat "$path") == "$content" ]]; then
    ok "Sin cambios: $path"
    return
  fi
  if [[ -f $path ]]; then
    local bk="${path}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$path" "$bk"
    warn "Backup existente -> $bk"
  fi
  printf '%s' "$content" > "$path"
  info "Escrito: $path"
}

# ---------- Actualización ----------
info "Sincronizando repos (pacman -Sy)"
sudo pacman -Sy --noconfirm

# ---------- VMware ----------
info "VMware guest tools"
pkg_install open-vm-tools gtkmm3 mesa jq

svc_enable vmtoolsd.service
svc_enable vmware-vmblock-fuse.service

# ---------- Hyprland (sin wofi, sin waybar, sin extras) ----------
info "Hyprland + utilidades mínimas"
pkg_install \
  hyprland \
  xdg-desktop-portal-hyprland \
  qt5-wayland qt6-wayland \
  polkit-kde-agent \
  wl-clipboard \
  pipewire pipewire-pulse wireplumber

# ---------- Ghostty ----------
info "Ghostty"
pkg_install ghostty

# ---------- Fuentes ----------
info "Fuentes"
pkg_install ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

# ---------- Config: Hyprland ----------
HYPR_CONF_DIR="$HOME/.config/hypr"
HYPR_CONF="$HYPR_CONF_DIR/hyprland.conf"

read -r -d '' HYPR_CONTENT << 'EOF' || true
# ---- Monitor ----
# El script vmware-autoresize se encarga de ajustar esto dinámicamente.
monitor = , preferred, auto, 1

# ---- Variables ----
$mainMod = SUPER
$terminal = ghostty

# ---- Autostart ----
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = /usr/bin/vmware-user-suid-wrapper
exec-once = ~/.config/hypr/vmware-autoresize.sh

# ---- Entorno (VMware Wayland) ----
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_RENDERER_ALLOW_SOFTWARE,1
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland;xcb

# ---- Input ----
input {
  kb_layout = es
  follow_mouse = 1
}

# ---- General ----
general {
  gaps_in = 5
  gaps_out = 10
  border_size = 2
  col.active_border = rgba(89b4faff)
  col.inactive_border = rgba(595959aa)
  layout = dwindle
}

decoration {
  rounding = 6
}

animations {
  enabled = no
}

dwindle {
  pseudotile = yes
  preserve_split = yes
}

# ---- Keybinds ----
bind = $mainMod, Return, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod SHIFT, M, exit,
bind = $mainMod, V, togglefloating,
bind = $mainMod, F, fullscreen,

# Foco
bind = $mainMod, left,  movefocus, l
bind = $mainMod, right, movefocus, r
bind = $mainMod, up,    movefocus, u
bind = $mainMod, down,  movefocus, d

# Workspaces
bind = $mainMod, 1, workspace, 1
bind = $mainMod, 2, workspace, 2
bind = $mainMod, 3, workspace, 3
bind = $mainMod, 4, workspace, 4
bind = $mainMod, 5, workspace, 5
bind = $mainMod SHIFT, 1, movetoworkspace, 1
bind = $mainMod SHIFT, 2, movetoworkspace, 2
bind = $mainMod SHIFT, 3, movetoworkspace, 3
bind = $mainMod SHIFT, 4, movetoworkspace, 4
bind = $mainMod SHIFT, 5, movetoworkspace, 5

# Mouse
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow
EOF
write_file "$HYPR_CONF" "$HYPR_CONTENT"

# ---------- Script de auto-resize ----------
AUTORESIZE="$HYPR_CONF_DIR/vmware-autoresize.sh"
read -r -d '' AUTORESIZE_CONTENT << 'EOF' || true
#!/usr/bin/env bash
# Detecta cambios en el tamaño preferido por VMware y lo aplica a Hyprland.
set -euo pipefail

MODES_FILE=$(ls /sys/class/drm/card*-Virtual-*/modes 2>/dev/null | head -n1 || true)
[[ -z $MODES_FILE ]] && { echo "No se encontró DRM de VMware"; exit 1; }

# Esperar a que Hyprland esté listo
for _ in {1..30}; do
  hyprctl monitors -j &>/dev/null && break
  sleep 1
done

MONITOR=$(hyprctl -j monitors | jq -r '.[0].name')
LAST=""

while true; do
  PREFERRED=$(head -n1 "$MODES_FILE" 2>/dev/null || true)
  if [[ -n $PREFERRED && $PREFERRED != "$LAST" ]]; then
    hyprctl keyword monitor "$MONITOR,${PREFERRED}@60,0x0,1" >/dev/null
    LAST=$PREFERRED
  fi
  sleep 1
done
EOF
write_file "$AUTORESIZE" "$AUTORESIZE_CONTENT"
chmod +x "$AUTORESIZE"

# ---------- Config: Ghostty ----------
GHOSTTY_CONF="$HOME/.config/ghostty/config"
read -r -d '' GHOSTTY_CONTENT << 'EOF' || true
font-family = JetBrainsMono Nerd Font
font-size   = 13
theme       = catppuccin-mocha

window-padding-x = 10
window-padding-y = 10

cursor-style       = block
cursor-style-blink = true

scrollback-limit      = 10000
copy-on-select        = true
confirm-close-surface = false
EOF
write_file "$GHOSTTY_CONF" "$GHOSTTY_CONTENT"

# ---------- Config: fontconfig ----------
FONTS_CONF="$HOME/.config/fontconfig/fonts.conf"
read -r -d '' FONTS_CONTENT << 'EOF' || true
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Noto Serif</family></prefer>
  </alias>
</fontconfig>
EOF
write_file "$FONTS_CONF" "$FONTS_CONTENT"

# Refrescar cache de fuentes solo si hay cambios
if fc-list | grep -qi "JetBrainsMono Nerd"; then
  ok "Cache de fuentes OK"
else
  info "Regenerando cache de fuentes"
  fc-cache -f >/dev/null
fi

# ---------- Resumen ----------
echo
echo "================================================"
echo "  Setup completo."
echo "  Reinicia con:   sudo reboot"
echo "  Desde tty:      Hyprland"
echo
echo "  SUPER+Return       -> Ghostty"
echo "  SUPER+Q            -> cerrar ventana"
echo "  SUPER+SHIFT+M      -> salir de Hyprland"
echo "  SUPER+F            -> fullscreen"
echo "  SUPER+1..5         -> workspaces"
echo "================================================"
