#!/bin/bash
# ============================================================
#  install.sh - Instalador para Asterisk PBX (PJSIP)
#  Voz + Video + Mensajes de texto + TLS + Fail2Ban
#  Ubuntu 22.04 / 24.04
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}OK: $1${NC}"; }
warn(){ echo -e "${YELLOW}AVISO: $1${NC}"; }
err() { echo -e "${RED}ERROR: $1${NC}"; exit 1; }

[[ $EUID -ne 0 ]] && err "Ejecuta como root: sudo ./install.sh"

echo "=================================================="
echo "  Instalador Asterisk PBX - PJSIP"
echo "=================================================="
echo ""
read -p "Dominio (ej: tudominio.duckdns.org): " DOMAIN
[[ -z "$DOMAIN" ]] && err "El dominio es obligatorio (necesario para TLS/Let's Encrypt)"

read -p "Email para Let's Encrypt: " LE_EMAIL
[[ -z "$LE_EMAIL" ]] && err "El email es obligatorio para certbot"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- 1. Verificar que Asterisk ya esté instalado ----
if ! command -v asterisk &> /dev/null; then
  err "Asterisk no está instalado. Instálalo primero (ver README de compilación) y vuelve a correr este script."
fi
ok "Asterisk encontrado: $(asterisk -V)"

# ---- 2. Verificar módulo PJSIP disponible ----
asterisk -rx 'module show like res_pjsip' | grep -q "res_pjsip.so" \
  || err "PJSIP no está compilado en tu Asterisk. Recompila con soporte PJSIP."
ok "Módulo PJSIP disponible"

# ---- 3. Respaldar configuración actual ----
BACKUP_DIR="/etc/asterisk.backup-$(date +%Y%m%d-%H%M%S)"
cp -r /etc/asterisk "$BACKUP_DIR"
ok "Respaldo creado en $BACKUP_DIR"

# ---- 4. Copiar configuración nueva ----
warn "Copiando archivos de configuración..."
cp "$REPO_DIR"/etc/asterisk/*.conf /etc/asterisk/

# Desactivar chan_sip si el archivo viejo existe
if [[ -f /etc/asterisk/sip.conf ]]; then
  mv /etc/asterisk/sip.conf /etc/asterisk/sip.conf.disabled
  warn "sip.conf viejo desactivado (renombrado a sip.conf.disabled)"
fi

# Reemplazar placeholders con el dominio real
sed -i "s/CHANGE_ME_PUBLIC_IP_OR_DOMAIN/$DOMAIN/g" /etc/asterisk/pjsip.conf
sed -i "s/CHANGE_ME_DOMAIN/$DOMAIN/g" /etc/asterisk/pjsip.conf

chown -R asterisk:asterisk /etc/asterisk/*.conf
chmod 640 /etc/asterisk/*.conf
ok "Configuración copiada y placeholders reemplazados con: $DOMAIN"

# ---- 5. Generar contraseñas aleatorias para cada extensión ----
warn "Generando contraseñas seguras para las 18 extensiones..."
for ext in 1000 1001 1002 1003 1004 1005 2000 2001 2002 2003 2004 2005 3000 3001 3002 3003 3004 3005; do
  newpass=$(openssl rand -base64 16 | tr -d '/+=' | head -c 20)
  sed -i "s/CHANGE_ME_$ext/$newpass/g" /etc/asterisk/pjsip.conf
  echo "  $ext -> $newpass"
done > /root/asterisk-extension-passwords.txt
cat /root/asterisk-extension-passwords.txt
chmod 600 /root/asterisk-extension-passwords.txt
ok "Contraseñas guardadas en /root/asterisk-extension-passwords.txt (chmod 600)"

# ---- 6. Certificado TLS con Let's Encrypt ----
warn "Generando certificado TLS..."
if ! command -v certbot &> /dev/null; then
  apt install -y certbot
fi

systemctl stop asterisk
certbot certonly --standalone --non-interactive --agree-tos \
  -m "$LE_EMAIL" -d "$DOMAIN" \
  || warn "Certbot falló. Verifica que el puerto 80 esté libre y el dominio apunte a este servidor. TLS quedará deshabilitado."

if [[ -d "/etc/letsencrypt/live/$DOMAIN" ]]; then
  chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/live
  PRIVKEY_REAL=$(readlink -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem")
  chown root:asterisk "$PRIVKEY_REAL"
  chmod 640 "$PRIVKEY_REAL"
  ok "Certificado TLS instalado y permisos ajustados para Asterisk"
else
  warn "No se encontró el certificado. Comenta el bloque [transport-tls] en pjsip.conf si no lo vas a usar."
fi

# ---- 7. Directorios de medios ----
mkdir -p /var/lib/asterisk/moh/{default,ventas,soporte,administracion}
mkdir -p /var/lib/asterisk/sounds/custom
mkdir -p /var/spool/asterisk/monitor
chown -R asterisk:asterisk /var/lib/asterisk /var/spool/asterisk
ok "Directorios de medios creados"

# ---- 8. Fail2Ban ----
warn "Configurando Fail2Ban..."
if ! command -v fail2ban-client &> /dev/null; then
  apt install -y fail2ban
fi
cp "$REPO_DIR"/etc/fail2ban/jail.d/asterisk.conf /etc/fail2ban/jail.d/
systemctl restart fail2ban
ok "Fail2Ban configurado (filtro de fábrica 'asterisk' + backend polling)"

# ---- 9. Firewall ----
warn "Configurando UFW..."
if command -v ufw &> /dev/null; then
  ufw allow 22/tcp
  ufw allow 5060/udp
  ufw allow 5060/tcp
  ufw allow 5061/tcp
  ufw allow 10000:20000/udp
  ufw --force enable
  ok "UFW configurado"
else
  warn "UFW no está instalado, configura tu firewall manualmente"
fi

# ---- 10. Iniciar Asterisk ----
warn "Iniciando Asterisk..."
systemctl start asterisk
sleep 5

if systemctl is-active --quiet asterisk; then
  ok "Asterisk corriendo correctamente"
else
  err "Asterisk no arrancó. Revisa: journalctl -u asterisk -n 50"
fi

echo ""
echo "=================================================="
echo -e "${GREEN}  INSTALACION COMPLETADA${NC}"
echo "=================================================="
echo ""
echo "  Dominio:     $DOMAIN"
echo "  Puerto SIP:  5060 (UDP/TCP), 5061 (TLS)"
echo "  Contrasenas: /root/asterisk-extension-passwords.txt"
echo ""
asterisk -rx 'pjsip show endpoints' | tail -5
echo ""
asterisk -rx 'pjsip show transports'
echo ""
fail2ban-client status asterisk
