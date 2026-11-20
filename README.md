# udm-voip

Persistent ISP VoIP VLAN support for UniFi OS, with optional UniFi Talk integration.

Many ISPs deliver telephony on a dedicated, tagged VLAN that UniFi OS does not
configure on its own. `udm-voip` brings up that VLAN, keeps a DHCP lease on it
across reboots and firmware restarts, routes only the provider's IMS networks
over it, and (optionally) patches UniFi Talk's FreeSWITCH ACL so registration
from those networks is accepted.

Initial profile: **Vodafone Portugal FTTH**.

Tested on:

- UniFi Dream Machine SE
- UniFi OS 5.1.31
- Vodafone PT FTTH
- UniFi Talk / FreeSWITCH

## Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Configuration](#configuration)
4. [UniFi Talk provider: Vodafone PT](#unifi-talk-provider-vodafone-pt)
5. [Usage](#usage)
6. [Upgrading](#upgrading)
7. [Removal](#removal)
8. [Troubleshooting](#troubleshooting)
9. [License](#license)

## Prerequisites

- A UniFi OS device (UDM / UDM Pro / UDM SE / UDR) with root SSH access.
- An ISP that delivers VoIP on a tagged VLAN on the WAN port.
- `systemd`, `busybox`, `python3` and `iptables` on the device — all present on
  stock UniFi OS. The installer checks for them and stops if one is missing.

Run everything below in **UniFi OS**, not inside the UbiOS/UniFi Network
container.

## Installation

Access your device over SSH and run, as root:

```sh
sh -c "$(curl https://raw.githubusercontent.com/Hannimal/udm-voip/main/install.sh -sSf)"
```

The script downloads the repository, installs the service files under
`/data/udm-voip`, enables `udm-voip.service` and `udm-voip-acl-proxy.service`,
and starts them immediately. Both services launch automatically at boot.

Alternatively, clone the repository and run the installer from the checkout:

```sh
git clone https://github.com/Hannimal/udm-voip.git
cd udm-voip
./install.sh
```

Once it finishes, verify the result:

```sh
udm-voip diagnose
```

### Migrating an existing manual setup

If an earlier hand-rolled `vodafone-voip.service` setup is present, the
installer cuts over to it automatically:

1. Backs it up under `/data/udm-voip/legacy-backup/`.
2. Stops the old ACL proxy.
3. Starts the new ACL proxy.
4. Stops the old DHCP/network service.
5. Starts `udm-voip` immediately.
6. Removes the old systemd units and experimental routing/NAT rules.

The old `/data/vodafone-voip` directory is left untouched as an additional
rollback copy. The migration can also be re-run by hand with
`udm-voip migrate-legacy`.

### Installation across firmware updates

A UniFi OS firmware update wipes `/usr/local/sbin` and
`/etc/systemd/system`, so `udm-voip` must be reinstalled afterwards. Re-running
the installer is enough — `/data` survives the update, so the saved
configuration and the original FreeSWITCH backup are preserved. Take a backup of
`/etc/udm-voip.conf` and `/data/udm-voip` before a major upgrade regardless.

## Configuration

`/etc/udm-voip.conf` selects which provider profile to load:

```sh
VOIP_PROFILE="vodafone-pt"
```

Switch profiles with:

```sh
udm-voip configure vodafone-pt
```

The per-provider defaults live in `/data/udm-voip/profiles/<profile>.conf`.
The selected profile is loaded first and `/etc/udm-voip.conf` is applied on top
of it, so any value set there overrides the profile. To change a single setting,
add it to `/etc/udm-voip.conf` and leave the profile untouched:

```sh
VOIP_PROFILE="vodafone-pt"

# Override just the WAN port; everything else comes from the profile.
VOIP_WAN_INTERFACE="eth8"
```

`udm-voip configure` rewrites only the `VOIP_PROFILE` line, so overrides survive
a profile switch. The main options are:

| Option | Description |
| --- | --- |
| `VOIP_WAN_INTERFACE` | Physical WAN port carrying the tagged VoIP VLAN (e.g. `eth9`). |
| `VOIP_WAN_VLAN` | VoIP VLAN ID (e.g. `101`). |
| `VOIP_INTERFACE` | Name given to the created VLAN interface (e.g. `voip`). |
| `VOIP_DHCP` | Whether to request a DHCP lease on the VoIP VLAN. |
| `VOIP_ROUTE_TABLE` | Policy routing table used for the IMS routes. |
| `VOIP_RULE_PRIORITY` | `ip rule` priority sending the IMS ranges to that table; must be below UniFi's multi-WAN rules. |
| `VOIP_IMS_RANGES` | Provider IMS networks routed over the VoIP VLAN. |
| `VOIP_TALK_ACL_RANGES` | Networks added to FreeSWITCH's `talk_acl`. |
| `VOIP_TALK_SOURCE` / `VOIP_TALK_SOURCE_INTERFACE` | Source address advertised to UniFi Talk; `auto` picks the first IPv4 on the interface. |
| `VOIP_TALK_XML_PROXY_PORT` | Port the local ACL proxy listens on in front of UniFi Talk's XML backend. |

Adding a provider means dropping a new `.conf` into
`/data/udm-voip/profiles/` (and `profiles/` in this repository) and selecting it
with `udm-voip configure <profile>`.

## UniFi Talk provider: Vodafone PT

Configure a custom SIP provider in UniFi Talk with:

```text
Server: ims.vodafone.pt
Port: 5060
Transport: UDP
Username: +351XXXXXXXXX
Auth Username: +351XXXXXXXXX
From User: +351XXXXXXXXX
Realm: ims.vodafone.pt
Password: Vodafone Access ID
Outbound Proxy: empty
```

## Usage

```sh
udm-voip status          # systemd status of both services
udm-voip restart         # restart services and reload FreeSWITCH
udm-voip diagnose        # full health check
udm-voip configure NAME  # select a provider profile
udm-voip reload-acl      # reload mod_xml_curl and the FreeSWITCH ACL
udm-voip migrate-legacy  # re-run the legacy setup migration
udm-voip uninstall       # remove udm-voip
```

## Upgrading

There is no self-update subcommand; upgrade by re-running the installer, which
overwrites the installed files in place:

```sh
sh -c "$(curl https://raw.githubusercontent.com/Hannimal/udm-voip/main/install.sh -sSf)"
```

`/etc/udm-voip.conf` is preserved if it already exists, as is the original
FreeSWITCH `xml_curl.conf.xml` kept for rollback.

## Removal

```sh
udm-voip uninstall
```

This disables both services, tears down the VLAN interface and routes, restores
the original FreeSWITCH `xml_curl.conf.xml`, and removes `/data/udm-voip`,
`/etc/udm-voip.conf` and the installed units.

## Troubleshooting

Start with the built-in health check:

```sh
udm-voip diagnose
```

A healthy system reports something like:

```text
voip interface: Vodafone DHCP address
213.30.55.0/27 -> voip
213.30.59.0/24 -> voip
Vodafone Talk gateway: REGED
acl 213.30.59.131 talk_acl: true
```

### Quick recovery

```sh
udm-voip restart
sleep 5
udm-voip diagnose
```

### SIP capture

```sh
tcpdump -ni any -nn -s0 -A \
  '((net 213.30.59.0/24 or net 213.30.55.0/27) and udp port 5060)'
```

### Installed files

```text
/etc/udm-voip.conf
/data/udm-voip/
/etc/systemd/system/udm-voip.service
/etc/systemd/system/udm-voip-acl-proxy.service
/usr/local/sbin/udm-voip
```

### Note on routing

`udm-voip` never replaces the normal UniFi WAN default route. Only
provider-specific IMS networks are routed through the VoIP VLAN.

The IMS ranges are routed through table `VOIP_ROUTE_TABLE`, selected by an
`ip rule` at priority `VOIP_RULE_PRIORITY` (default `10101`). This matters with
**multi-WAN** (failover or load balancing): UniFi then adds its own policy
rules (fwmark and per-WAN tables such as `201`/`202`) that are evaluated before
the `main` table, so a route in `main` alone is ignored and SIP leaves through a
WAN port. `udm-voip diagnose` shows the rules and the route the IMS traffic
actually takes.

## License

GPL-2.0-only.
