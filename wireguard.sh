#!/bin/bash

sudo apt update -y && sudo apt upgrade -y && sudo apt install ufw wireguard -y

echo
echo "####################### VPN CONFIGURATION #######################"
echo "Mind you that entering erroneous information may render the Wireguard Interface unusable."
echo "Enter the Wireguard Interface name: "
read -rp "-> " WIREGUARD_INTERFACE
echo "Enter an IPv4 (Class B) without CIDR. Example: 10.0.0.1"
read -rp "-> " IPV4
echo "Enter a CIDR for the network (IPV4). Example: /16"
read -rp "-> " IPV4_CIDR
echo "Enter a CIDR for the network (IPV6). Example: /64"
read -rp "-> " IPV6_CIDR
echo "Enter the Wireguard Listen Port. Example: 51820"
read -rp "-> " PORT

sudo ufw enable && sudo ufw allow $PORT

wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key > /dev/null && \
sudo chmod go= /etc/wireguard/private.key

IPV4_LAST_OCTET=$( printf $IPV4 | cut -d. -f4 | cut -d/ -f1 )
IPV6_TIMESTAMP=fd$( printf $( date +%s%N )$( cat /var/lib/dbus/machine-id ) | sha1sum )
IPV6=,$( printf fd$( printf $IPV6_TIMESTAMP | cut -c 31- ) | cut -c 1-4 ):$( printf fd$( printf $IPV6_TIMESTAMP | cut -c 31- ) | cut -c 5-8 ):$( printf fd$( printf $IPV6_TIMESTAMP | cut -c 31- ) | cut -c 9-12 )::$IPV4_LAST_OCTET
INTERFACE=$( ip route list default | awk '{print $5}' )

echo
echo "####################### GENERATED INTERFACE (/etc/wireguard/$WIREGUARD_INTERFACE.conf) #######################"
echo "[Interface]" | sudo tee /etc/wireguard/$WIREGUARD_INTERFACE.conf
echo "PrivateKey = [secret]" && echo "PrivateKey = $( sudo cat /etc/wireguard/private.key )" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf > /dev/null
echo "Address = $IPV4$IPV4_CIDR$IPV6$IPV6_CIDR" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "ListenPort = $PORT" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "SaveConfig = true" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf
echo "PostUp = ufw route allow in on $WIREGUARD_INTERFACE out on $INTERFACE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "PreDown = ufw route delete allow in on $WIREGUARD_INTERFACE out on $INTERFACE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "PostUp = iptables -t nat -I POSTROUTING -o $INTERFACE -j MASQUERADE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "PreDown = iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "PostUp = ip6tables -t nat -I POSTROUTING -o $INTERFACE -j MASQUERADE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf 
echo "PreDown = ip6tables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE" | sudo tee -a /etc/wireguard/$WIREGUARD_INTERFACE.conf

grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf  
grep -qxF "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf 
sudo sysctl -p > /dev/null

echo
echo "####################### WIREGUARD STATUS #######################"
sudo systemctl enable wg-quick@$WIREGUARD_INTERFACE
sudo systemctl start wg-quick@$WIREGUARD_INTERFACE
sudo systemctl status wg-quick@$WIREGUARD_INTERFACE

echo
echo "####################### SERVER PEER SETUP #######################"
echo "[Peer]"
echo "PublicKey = <client_peer_public_key>"
echo "AllowedIPs = $( printf $IPV4 | awk -F"." '{print $1"."$2"."$3".0"}' )$IPV4_CIDR$( printf $IPV6 | cut -d/ -f1 | sed 's/.$//' )$IPV6_CIDR"
echo "####################### END OF SERVER PEER SETUP #######################"
echo
echo "####################### CLIENT PEER SETUP #######################"
echo "[Interface]"
echo "PrivateKey = <client_peer_private_key>"
echo "Address = $( printf $(awk -F\. '{ print $1"."$2"."$3"."$4+1 }' <<< $IPV4 ) )/32$( printf $IPV6 | cut -d/ -f1 | awk -F\: '{ print $1":"$2":"$3"::"$5+1}' )/128"
echo "DNS = $( grep "nameserver" /etc/resolv.conf | awk '{print $2'} )"
echo
echo "[Peer]"
echo "PublicKey = $( sudo cat /etc/wireguard/public.key )"
echo "AllowedIPs = $( printf $IPV4 | awk -F"." '{print $1"."$2"."$3".0"}' )$IPV4_CIDR$( printf $IPV6 | cut -d/ -f1 | sed 's/.$//' )$IPV6_CIDR"
echo "Endpoint = $( host myip.opendns.com resolver1.opendns.com | grep address | awk '{print $4}' ):$PORT"
echo "PersistentKeepalive = 25"
echo "####################### END OF CLIENT PEER #######################"

# To add peer to server from shell:
# sudo wg set intranet peer p9C3tb7CSAz4PNGnaHWpGiLbcBzgGAvFBs8BwRwe2C0= allowed-ips 10.10.0.0/20,fd18:d2bb:3f25::/64
