# 📞 Asterisk PBX — Voz, Video y Mensajería de Texto

Configuración completa de Asterisk 20 con **PJSIP** lista para producción: voz, videollamadas, mensajes de texto SIP, buzón de voz, colas ACD, IVR, conferencias, TLS/SRTP y protección anti fuerza-bruta con Fail2Ban.

Diseñado para que **cualquier dispositivo pueda registrarse desde cualquier red** (no solo LAN local) usando un dominio dinámico (DuckDNS, No-IP, etc.) o IP pública fija.

## 📋 Características

- **18 extensiones** organizadas en 3 departamentos (1000-1005, 2000-2005, 3000-3005)
- **Voz**: Opus, G.722, G.711 (a-law/u-law), GSM
- **Video**: VP8, H.264, H.265
- **Mensajería**: SIP MESSAGE (texto plano entre extensiones)
- **Cifrado**: TLS para señalización + SRTP para medios
- **Buzón de voz** con notificación, **colas ACD**, **IVR**, **salas de conferencia**
- **Fail2Ban** preconfigurado contra ataques de registro SIP

## 🗂️ Estructura del repositorio

```
etc/asterisk/
├── pjsip.conf          Extensiones SIP, transportes (UDP/TCP/TLS)
├── extensions.conf     Dialplan: llamadas, IVR, colas, texto, buzón
├── voicemail.conf      Buzones de voz para las 18 extensiones
├── queues.conf         Colas ACD por departamento
├── confbridge.conf     Salas de conferencia con video
├── features.conf       Transferencias, parking, grabación
├── rtp.conf             Puertos RTP, ICE/STUN
├── musiconhold.conf    Música en espera por departamento
├── modules.conf        Desactiva chan_sip, fuerza módulos PJSIP
├── manager.conf        AMI (acceso administrativo)
├── logger.conf         Configuración de logs
└── cdr.conf             Registro de llamadas

etc/fail2ban/
├── jail.d/asterisk.conf      Jail anti fuerza-bruta
└── filter.d/                 (usa el filtro asterisk.conf de fábrica)

scripts/
└── asterisk-setup.sh   Instalador automático
```

## 🚀 Instalación rápida

```bash
git clone <tu-repo>
cd asterisk-pbx-config

# 1. Reemplaza los placeholders con tus datos reales
#    CHANGE_ME_PUBLIC_IP_OR_DOMAIN -> tu IP pública o dominio
#    CHANGE_ME_DOMAIN              -> tu dominio (para TLS)
#    CHANGE_ME_XXXX                -> contraseña de cada extensión
sed -i 's/CHANGE_ME_PUBLIC_IP_OR_DOMAIN/tudominio.duckdns.org/g' etc/asterisk/pjsip.conf
sed -i 's/CHANGE_ME_DOMAIN/tudominio.duckdns.org/g' etc/asterisk/pjsip.conf

# 2. Copia la configuración al servidor
sudo cp etc/asterisk/*.conf /etc/asterisk/
sudo cp etc/fail2ban/jail.d/asterisk.conf /etc/fail2ban/jail.d/
sudo chown asterisk:asterisk /etc/asterisk/*.conf

# 3. Certificado TLS (Let's Encrypt, requiere dominio apuntando al servidor)
sudo apt install -y certbot
sudo systemctl stop asterisk
sudo certbot certonly --standalone -d tudominio.duckdns.org
# Dale acceso de lectura a Asterisk sobre la clave privada
sudo chmod 755 /etc/letsencrypt/archive /etc/letsencrypt/live
sudo chown root:asterisk /etc/letsencrypt/archive/tudominio.duckdns.org/privkey*.pem
sudo chmod 640 /etc/letsencrypt/archive/tudominio.duckdns.org/privkey*.pem

# 4. Iniciar
sudo systemctl start asterisk
sudo systemctl restart fail2ban
sleep 5
asterisk -rx 'pjsip show endpoints'   # debe mostrar 18 objetos
asterisk -rx 'pjsip show transports'  # debe mostrar udp, tcp y tls
```

## ⚠️ Notas críticas aprendidas en producción

1. **No uses templates con nombres distintos** (`endpoint-tpl`, `1002-auth`, `1002-aor`) — el motor *sorcery* de PJSIP puede rechazar objetos silenciosamente sin loguear el error. Usa el mismo nombre de sección para los tres bloques (`[1002]` repetido), tal como está en este repo.
2. **Evita acentos/tildes** en los archivos `.conf` — un encoding corrupto en un comentario puede romper el parser de sorcery para todo lo que viene después en el archivo, sin mensaje de error claro.
3. **TLS no es recargable** (`pjsip reload` no aplica cambios de certificado) — requiere `systemctl restart asterisk` completo.
4. **Let's Encrypt restringe permisos** de `privkey.pem` a solo `root` — Asterisk corre como usuario `asterisk` y no podrá leer el certificado hasta que ajustes permisos (ver paso 3 arriba).
5. **UFW puede neutralizar Fail2Ban** silenciosamente — si usas UFW, asegúrate que la cadena `f2b-asterisk` esté **antes** que `ufw-before-input` en `INPUT` (usa `chain=INPUT` en la acción de Fail2Ban, como en este repo) y que incluya tanto TCP como UDP.
6. **Fail2Ban necesita `backend=polling`** en este setup — Asterisk no escribe estos logs en el journal de systemd por defecto, así que el backend `systemd` no detecta nada.

## 🔐 Seguridad

- Cambia **todas** las contraseñas `CHANGE_ME_XXXX` antes de exponer el servidor a Internet
- Fail2Ban bloquea automáticamente IPs tras 3 intentos fallidos en 5 minutos (ban de 24h)
- Activa TLS para evitar contraseñas en texto plano en la red

## 📱 Conectar un cliente (Linphone, Zoiper, etc.)

| Campo | Valor |
|---|---|
| Servidor | tu dominio o IP pública |
| Puerto | `5060` (UDP/TCP) o `5061` (TLS) |
| Usuario | número de extensión (ej. `1002`) |
| Contraseña | la que configuraste en `pjsip.conf` |

## 📜 Licencia

Úsalo libremente, adaptado a tu propia infraestructura.
