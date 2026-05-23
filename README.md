# VPN - VLESS Reality Automated Setup

Automated configuration scripts for VLESS-Reality proxy server using the 3X-UI panel. These scripts complete Steps 6-7 of the setup guide after the 3X-UI panel has been installed (Step 5).

## What This Does

1. **Connects** to your VPS via SSH tunnel
2. **Hardens** the 3X-UI panel security:
   - Changes default credentials
   - Binds panel to localhost (accessible only via SSH tunnel)
   - Changes default port and URL path
3. **Configures routing** on the server:
   - Blocks BitTorrent traffic
   - Blocks access to Russian domains through the proxy
4. **Creates VLESS-Reality inbound** with:
   - Protocol: VLESS over TCP
   - Security: Reality (XTLS-Reality)
   - Flow: xtls-rprx-vision
   - Port: 443
   - uTLS fingerprint masquerading
5. **Generates client configurations**:
   - VLESS URLs for import into client apps
   - QR codes (if `qrencode` is installed)
   - Nekoray routing rules JSON

## Prerequisites

- VPS server with 3X-UI panel installed and running (Step 5 completed)
- SSH access to the server
- Tools: `curl`, `jq`, `openssl`, `ssh`, `sshpass`

## Usage

### Option 1: Using Environment Variables (Recommended for CI/CD)

Set the required secrets in your Cursor Dashboard (Cloud Agents > Secrets):

| Variable | Required | Default | Description |
|---|---|---|---|
| `VPS_HOST` | Yes | - | VPS IP address |
| `VPS_SSH_PORT` | No | `22` | SSH port |
| `VPS_SSH_USER` | No | `root` | SSH username |
| `VPS_SSH_PASSWORD` | Yes | - | SSH password |
| `PANEL_PORT` | No | `2053` | Current 3X-UI panel port |
| `PANEL_USER` | No | `admin` | Current panel username |
| `PANEL_PASS` | No | `admin` | Current panel password |
| `DEST_DOMAIN` | No | `www.samsung.com` | Masquerading domain |
| `CLIENT_NAMES` | No | `MyPC,MyPhone` | Comma-separated client device names |
| `UTLS_FINGERPRINT` | No | `chrome` | uTLS fingerprint (`chrome`, `firefox`, etc.) |
| `SKIP_HARDENING` | No | `false` | Skip panel security hardening |

Then run:

```bash
bash scripts/setup_vless_reality.sh
```

### Option 2: Interactive Mode

```bash
bash scripts/quick_setup.sh
```

This will prompt for all required parameters interactively.

## Output Files

After running the script, all configuration files are saved to `output/`:

| File | Description |
|---|---|
| `client_configs.txt` | VLESS URLs and manual config for each client |
| `panel_credentials.txt` | New panel access credentials (after hardening) |
| `nekoray_routing.json` | Ready-to-import routing rules for Nekoray |
| `setup_summary.txt` | Complete setup summary |
| `setup_*.log` | Detailed execution log |
| `qr_*.png` | QR codes for mobile clients (if `qrencode` is installed) |

## After Setup - Client Configuration

### PC (Nekoray / Hiddify-Next)

1. Copy the VLESS URL from `output/client_configs.txt`
2. In Nekoray: Server -> Add profile from clipboard
3. Import routing rules from `output/nekoray_routing.json`
4. Enable TUN mode and System Proxy
5. Start the connection

### Android (Nekobox / V2RayNG)

1. Scan the QR code from `output/qr_*.png` or copy the VLESS URL
2. Import into the app
3. Configure routing rules for Russian domains (bypass)
4. Enable VPN mode

### iOS (FoXray / Shadowrocket)

1. Scan the QR code or import the VLESS URL
2. Verify all connection parameters match
3. Enable the proxy

## Verification

After connecting via the client app:

1. Visit [ipinfo.io](https://ipinfo.io/) - should show your VPS IP address
2. Visit [2ip.ru](https://2ip.ru/) - should show your real (Russian) IP address
3. Test Discord, YouTube, and other blocked services

## Security Notes

- Panel is bound to `127.0.0.1` and accessible only via SSH tunnel
- Default credentials are changed to randomly generated ones
- BitTorrent traffic is blocked on the server
- Russian domain traffic is blocked on the server side (extra safety)
- Each client device should use its own unique client profile

## File Structure

```
scripts/
  setup_vless_reality.sh   # Main setup script
  quick_setup.sh            # Interactive wrapper
  xui_api.sh                # 3X-UI API library
  generate_keys.sh          # Key generation utilities
output/                      # Generated after running setup
  client_configs.txt
  panel_credentials.txt
  nekoray_routing.json
  setup_summary.txt
```
