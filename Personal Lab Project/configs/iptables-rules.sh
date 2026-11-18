#!/bin/bash
# Perimeter Firewall & NFQUEUE Redirection Rules (Ubuntu Gateway)

# --- Lab 03: Stateless Perimeter Blocking ---
# Silently drop transit Telnet (TCP Port 23) traffic across the FORWARD chain
sudo iptables -A FORWARD -p tcp --dport 23 -j DROP

# --- Lab 04: Inline NIPS Integration (DAQ NFQUEUE) ---
# Redirect transit Telnet packets from kernel space to Netfilter Queue 0 for Snort inspection
# (Flush or replace the stateless DROP rule above before applying NFQUEUE)
# sudo iptables -A FORWARD -p tcp --dport 23 -j NFQUEUE --queue-num 0