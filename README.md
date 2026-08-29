# udm-voip

Persistent ISP VoIP VLAN support for UniFi OS with optional UniFi Talk integration.

Initial profile: **Vodafone Portugal FTTH**.

Tested on:

- UniFi Dream Machine SE
- UniFi OS 5.1.31
- Vodafone PT FTTH
- UniFi Talk / FreeSWITCH

## Install

Copy/clone the repository to the UDM and run as root:

```sh
./install.sh
```

If the earlier manual `vodafone-voip.service` setup exists, the installer automatically:

1. Backs it up under `/data/udm-voip/legacy-backup/`.
2. Stops the old ACL proxy.
3. Starts the new ACL proxy.
4. Stops the old DHCP/network service.
5. Starts `udm-voip` immediately.
6. Removes the old systemd units and experimental routing/NAT rules.

The old `/data/vodafone-voip` directory is left untouched as an additional rollback copy.

Then run:

```sh
udm-voip diagnose
```

## UniFi Talk provider — Vodafone PT

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

## Commands

```sh
udm-voip status
udm-voip restart
udm-voip diagnose
udm-voip configure vodafone-pt
udm-voip reload-acl
udm-voip migrate-legacy
udm-voip uninstall
```

## Healthy state

```sh
udm-voip diagnose
```

Key results:

```text
voip interface: Vodafone DHCP address
213.30.55.0/27 -> voip
213.30.59.0/24 -> voip
Vodafone Talk gateway: REGED
acl 213.30.59.131 talk_acl: true
```

## Quick recovery

```sh
udm-voip restart
sleep 5
udm-voip diagnose
```

## SIP capture

```sh
tcpdump -ni any -nn -s0 -A \
  '((net 213.30.59.0/24 or net 213.30.55.0/27) and udp port 5060)'
```

## Files

```text
/etc/udm-voip.conf
/data/udm-voip/
/etc/systemd/system/udm-voip.service
/etc/systemd/system/udm-voip-acl-proxy.service
/usr/local/sbin/udm-voip
```

## Important

`udm-voip` never replaces the normal UniFi WAN default route. Only provider-specific IMS networks are routed through the VoIP VLAN.

## License

GPL-2.0-only.
