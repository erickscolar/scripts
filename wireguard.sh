#!/bin/bash

sudo apt update -y && sudo apt install ufw wireguard -y
echo
echo "####################### OPENING PORTS 22 (OpenSSH) and 51820 (Wireguard) #######################"
sudo ufw allow OpenSSH
sudo ufw allow 51820/udp
echo
echo "####################### ENABLING UFW #######################"
sudo ufw enable

wg genkey | sudo tee /etc/wireguard/private.key > /dev/null
sudo chmod go= /etc/wireguard/private.key
sudo cat /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key > /dev/null

# 'fd' in ipv6_address means local network
public_interface=$( ip route list default | awk '{print $5}' )
ipv4_address=$( ip route | grep src | grep $public_interface | awk '{print $3}' | sed "${1}q;d" )
ipv6_address=$( printf fd$( date +%s%N )$( cat /var/lib/dbus/machine-id | sha1sum | cut -c 31- ) | cut -c 1-4 )::$( printf fd$( date +%s%N )$( cat /var/lib/dbus/machine-id | sha1sum | cut -c 31- ) | cut -c 5-8 )::$( printf fd$( date +%s%N )$( cat /var/lib/dbus/machine-id | sha1sum | cut -c 31- ) | cut -c 9-12 )::1/64

echo
echo "####################### GENERATED INTERFACE (/etc/wireguard/wg0.conf) #######################"
echo "[Interface]" | sudo tee /etc/wireguard/wg0.conf
echo "PrivateKey = [secret]"
echo "PrivateKey = $( sudo cat /etc/wireguard/private.key )" | sudo tee -a /etc/wireguard/wg0.conf > /dev/null
echo "Address = $ipv4_address, $ipv6_address" | sudo tee -a /etc/wireguard/wg0.conf
echo "ListenPort = 51820" | sudo tee -a /etc/wireguard/wg0.conf
echo "SaveConfig = true" | sudo tee -a /etc/wireguard/wg0.conf
echo "PostUp = ufw route allow in on wg0 out on $public_interface" | sudo tee -a /etc/wireguard/wg0.conf
echo "PostUp = iptables -t nat -I POSTROUTING -o $public_interface -j MASQUERADE" | sudo tee -a /etc/wireguard/wg0.conf
echo "PostUp = ip6tables -t nat -I POSTROUTING -o $public_interface -j MASQUERADE" | sudo tee -a /etc/wireguard/wg0.conf
echo "PreDown = ufw route delete allow in on wg0 out on $public_interface" | sudo tee -a /etc/wireguard/wg0.conf
echo "PreDown = iptables -t nat -D POSTROUTING -o $public_interface -j MASQUERADE" | sudo tee -a /etc/wireguard/wg0.conf
echo "PreDown = ip6tables -t nat -D POSTROUTING -o $public_interface -j MASQUERADE" | sudo tee -a /etc/wireguard/wg0.conf

echo
echo "####################### FORWARDING SETUP (/etc/sysctl.conf) #######################"
grep -qxF "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf 
grep -qxF "net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf 
sudo sysctl -p

echo
sudo systemctl enable wg-quick@wg0.service
sudo systemctl start wg-quick@wg0.service
sudo systemctl status wg-quick@wg0.service
