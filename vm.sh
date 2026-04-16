#!/usr/bin/env bash
# ============================================================
# Setup Arch Linux en VMware + Hyprland + Ghostty
# Ejecutar como usuario normal (NO root). Pedirá sudo.
# ============================================================
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Ejecuta este script como usuario normal. Pedirá sudo cuando lo necesite."
  exit 1
fi

echo "==> Actualizando el sistema"
sudo pacman -Syu --noconfirm

# ---------- VMware guest tools ----------
echo "==> Instalando open-vm-tools y drivers de VMware"
sudo pacman -S --needed --noconfirm \
  open-vm-tools \
  gtkmm3 \
  xf86-input-vmmouse \
  xf86-video-vmware \
  mesa

echo "==> Habilitando servicios de VMware"
sudo systemctl enable --now vmtoolsd.service
sudo systemctl enable --now vmware-vmblock-fuse.service

# ---------- Hyprland + utilidades Wayland ----------
echo "==> Instalando Hyprland y utilidades"
sudo pacman -S --needed --noconfirm \
  hyprland \
  xdg-desktop-portal-hyprland \
  qt5-wayland qt6-wayland \
  polkit-kde-agent \
  waybar \
  wofi \
  hyprpaper \
  grim slurp wl-clipboard \
  mako \
  brightnessctl \
  pipewire pipewire-pulse wireplumber \
  thunar

# ---------- Ghostty ----------
echo "==> Instalando Ghostty"
sudo pacman -S --needed --noconfirm ghostty

# ---------- Fuentes legibles ----------
echo "==> Instalando Nerd Fonts y Noto"
sudo pacman -S --needed --noconfirm \
  ttf-jetbrains-mono-nerd \
  ttf-firacode-nerd \
  noto-fonts \
  noto-fonts-emoji \
  noto-fonts-cjk

# ---------- Config de Hyprland ----------
echo "==> Escribiendo ~/.config/hypr/hyprland.conf"
mkdir -p "$HOME/.config/hypr"
cat > "$HOME/.config/hypr/hyprland.conf" << 'EOF'
# ---- Monitor (VMware ajusta solo con open-vm-tools) ----
monitor = , preferred, auto, 1

# ---- Variables ----
$mainMod = SUPER
$terminal = ghostty
$menu = wofi --show drun
$fileManager = thunar

# ---- Autostart ----
exec-once = waybar
exec-once = mako
exec-once = hyprpaper
exec-once = /usr/lib/polkit-kde-authentication-agent-1
exec-once = /usr/bin/vmware-user-suid-wrapper

# ---- Variables de entorno (VMware suele necesitar software rendering) ----
env = WLR_NO_HARDWARE_CURSORS,1
env = WLR_RENDERER_ALLOW_SOFTWARE,1
env = XCURSOR_SIZE,24
env = QT_QPA_PLATFORM,wayland;xcb
env = MOZ_ENABLE_WAYLAND,1

# ---- Input ----
input {
  kb_layout = es
  follow_mouse = 1
  sensitivity = 0
  touchpad {
    natural_scroll = yes
  }
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

# ---- Decoración ----
decoration {
  rounding = 6
  blur {
    enabled = true
    size = 3
    passes = 1
  }
  shadow {
    enabled = true
    range = 4
    render_power = 3
    color = rgba(1a1a1aee)
  }
}

# ---- Animaciones ----
animations {
  enabled = yes
  bezier = myBezier, 0.05, 0.9, 0.1, 1.05
  animation = windows, 1, 7, myBezier
  animation = windowsOut, 1, 7, default, popin 80%
  animation = border, 1, 10, default
  animation = fade, 1, 7, default
  animation = workspaces, 1, 6, default
}

dwindle {
  pseudotile = yes
  preserve_split = yes
}

# ---- Keybinds ----
bind = $mainMod, RETURN, exec, $terminal
bind = $mainMod, Q, killactive,
bind = $mainMod SHIFT, M, exit,
bind = $mainMod, E, exec, $fileManager
bind = $mainMod, V, togglefloating,
bind = $mainMod, R, exec, $menu
bind = $mainMod, F, fullscreen,
bind = $mainMod, J, togglesplit,

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

# Scroll de workspaces con la rueda
bind = $mainMod, mouse_down, workspace, e+1
bind = $mainMod, mouse_up,   workspace, e-1

# Mover/redimensionar con el ratón
bindm = $mainMod, mouse:272, movewindow
bindm = $mainMod, mouse:273, resizewindow

# Screenshot al portapapeles
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy
EOF

# ---------- Config de Ghostty ----------
echo "==> Escribiendo ~/.config/ghostty/config"
mkdir -p "$HOME/.config/ghostty"
cat > "$HOME/.config/ghostty/config" << 'EOF'
# ---- Fuente ----
font-family = JetBrainsMono Nerd Font
font-size   = 13

# ---- Tema ----
theme = catppuccin-mocha

# ---- Ventana ----
window-padding-x   = 10
window-padding-y   = 10
background-opacity = 0.95
window-decoration  = false

# ---- Cursor ----
cursor-style       = block
cursor-style-blink = true

# ---- Scroll y comportamiento ----
scrollback-limit       = 10000
copy-on-select         = true
confirm-close-surface  = false

# ---- Shell integration ----
shell-integration = detect
EOF

# ---------- Fontconfig: monospace legible por defecto ----------
echo "==> Escribiendo ~/.config/fontconfig/fonts.conf"
mkdir -p "$HOME/.config/fontconfig"
cat > "$HOME/.config/fontconfig/fonts.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
      <family>FiraCode Nerd Font</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
    </prefer>
  </alias>
</fontconfig>
EOF

fc-cache -fv >/dev/null

echo ""
echo "=============================================="
echo "Listo. Reinicia la VM: sudo reboot"
echo ""
echo "Después del reinicio, desde el tty:"
echo "   Hyprland"
echo ""
echo "Atajos básicos:"
echo "   SUPER + RETURN     -> Ghostty"
echo "   SUPER + R          -> menú de apps (wofi)"
echo "   SUPER + Q          -> cerrar ventana"
echo "   SUPER + E          -> explorador de archivos"
echo "   SUPER + SHIFT + M  -> salir de Hyprland"
echo "   Print              -> captura de región al portapapeles"
echo "=============================================="
