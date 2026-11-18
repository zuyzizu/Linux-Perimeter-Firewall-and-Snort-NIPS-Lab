# End-to-End Network Defense: Perimeter Firewall (iptables) & Inline Snort NIDS/NIPS Lab

![Platform](https://img.shields.io/badge/Platform-Linux%20(Ubuntu%20%7C%20Kali)-blue)
![Firewall](https://img.shields.io/badge/Firewall-iptables%20%2F%20NFQUEUE-orange)
![IDS/IPS](https://img.shields.io/badge/IDS%2FIPS-Snort%202.9.20-red)
![Recon](https://img.shields.io/badge/Assessment-Nmap%20NSE%20%7C%20OpenVAS-green)

## Overview
This repository documents an end-to-end network security laboratory project demonstrating a complete *Cyber Attack & Defense Lifecycle* within a segmented virtual environment.

The architecture simulates an external threat actor attempting to enumerate and exploit a vulnerable internal server across a dual-homed Linux security gateway. Defense-in-depth controls are engineered progressively—spanning network segmentation, vulnerability assessment, stateless perimeter filtering (iptables), and active inline intrusion prevention (Snort NIPS via DAQ NFQUEUE).

---

## Network Architecture & Topology

text
+-------------------------+          +-----------------------------------------+          +-------------------------+
|      Attacker Host      |          |         Gateway / Defense Node          |          |       Victim Host       |
|      (Kali Linux)       |          |            (Ubuntu Server)              |          |    (Metasploitable2)    |
|                         |          |                                         |          |                         |
|  eth0: 10.10.1.128/24   |--------->|  ens38 (WAN): 10.10.1.1/24              |          |                         |
|        10.10.1.2/24     |   WAN    |  ens37 (LAN): 172.16.1.1/24             |--------->|  eth0: 172.16.1.2/24    |
|                         |  Subnet  |                                         |   LAN    |                         |
+-------------------------+          |  • Kernel IPv4 Packet Forwarding         |  Subnet  +-------------------------+
                                     |  • iptables Perimeter Packet Filtering  |
                                     |  • Snort NIDS / Inline NIPS (NFQUEUE)   |
                                     +-----------------------------------------+

### Node Specifications
| Node Role | Operating System | Interface(s) | IP Address / Subnet | Security Function |
| :--- | :--- | :--- | :--- | :--- |
| *External Attacker* | Kali Linux | eth0 | 10.10.1.128/24`<br>(10.10.1.2/24` secondary) | Reconnaissance, Service Enumeration & Exploitation |
| *Security Gateway* | Ubuntu Server | ens38 (WAN)<br>`ens37` (LAN) | 10.10.1.1/24`<br>172.16.1.1/24` | Inter-VLAN/Subnet Routing, iptables Firewall, Snort IDS/IPS |
| *Target Victim* | Metasploitable2 | eth0 | 172.16.1.2/24 | Intentionally Vulnerable Internal Target |

---

## Implementation Phases

### Phase 1: Isolated Network Environment & Routing Configuration
* Segmented the virtual topology into an untrusted WAN zone (10.10.1.0/24) and a protected LAN zone (172.16.1.0/24) bridged by a dual-homed Ubuntu router.
* Enabled Linux kernel IPv4 forwarding (net.ipv4.ip_forward=1) on the gateway and validated cross-subnet ICMP reachability (0% packet loss, <3 ms average RTT, 2-hop routing distance).

### Phase 2: Reconnaissance & Vulnerability Assessment
Conducted structured enumeration from Kali Linux (10.10.1.128) against the LAN target (172.16.1.2):
* **Host Discovery & Port Enumeration (nmap -Pn -n -sV -O):** Bypassed routed ICMP blocks using -Pn and -n, uncovering 23 exposed TCP services running on an outdated Linux 2.6.x kernel (2.6.9 - 2.6.33) lacking modern ASLR/SMEP/SMAP protections.
* **Automated Vulnerability Assessment (nmap --script vuln & OpenVAS):**
  * Engineering Troubleshooting Note: Deployed OpenVAS Community Edition via Greenbone Security Assistant (127.0.0.1:9392) and configured the target profile; when air-gapped lab constraints restricted NVT feed synchronization, proactively pivoted to *Nmap Scripting Engine (NSE)* vulnerability scripts to complete CVE mapping.

| Port / Protocol | Service & Version | Identified Vulnerability / CVE | Security Impact |
| :--- | :--- | :--- | :--- |
| 21/tcp | vsftpd 2.3.4 | Backdoor Command Execution (CVE-2011-2523) | Critical RCE granting immediate uid=0(root) shell |
| 23/tcp | Linux telnetd | Cleartext Authentication Protocol | Susceptible to credential sniffing & brute-force |
| 80/tcp, 8180/tcp | Apache 2.2.8 / Tomcat 1.1 | Slowloris DoS (CVE-2007-6750), CSRF, exposed /phpMyAdmin/, /dvwa/ | Connection pool exhaustion & web surface exposure |
| 1099/tcp | GNU Classpath grmiregistry | Java RMI Registry Default Configuration RCE | Remote arbitrary class loading & code execution |
| 1524/tcp | bindshell | Unauthenticated Metasploitable Root Shell | Direct root backdoor access |
| 25/tcp, SSL/TLS | Postfix / OpenSSL | DROWN (CVE-2016-0800), POODLE (CVE-2014-3566), Weak DH Group 1 | MITM decryption & downgrade attacks |

### Phase 3: Perimeter Network Security with iptables
Audited baseline policies (sudo iptables -L -n -v and sudo iptables -S, initially ACCEPT across all chains) and enforced perimeter filtering on the FORWARD chain—the exact traversal path for routed WAN-to-LAN traffic:

# Silently drop unauthorized Telnet (TCP Port 23) connection attempts traversing the gateway
sudo iptables -A FORWARD -p tcp --dport 23 -j DROP
* *Verification:* Subsequent telnet 172.16.1.2 attempts hung and timed out silently (no TCP RST or ICMP Port Unreachable leaked), and nmap -Pn -n -p 23 172.16.1.2 confirmed port 23/tcp shifted from open to filtered.

### Phase 4: Intrusion Detection (NIDS) & Inline Prevention (NIPS) with Snort

#### 1. Configuration Validation & Passive NIDS Mode
Validated rule chains and protocol preprocessors (SF_FTPTELNET, SF_DNS, SF_SSH) using sudo snort -T -c /etc/snort/snort.conf, then ran Snort on the WAN interface (ens38) to generate real-time alerts (sid:1000001):
sudo snort -A console -q -c /etc/snort/snort.conf -i ens38

#### 2. Upgrading to Active Inline NIPS via DAQ NFQUEUE
Integrated iptables with Snort in inline mode so transit packets are held in kernel memory, inspected in user-space by Snort, and dropped before entering the LAN:

# Step 1: Redirect transit Telnet packets from Linux kernel space to Netfilter Queue 0
sudo iptables -A FORWARD -p tcp --dport 23 -j NFQUEUE --queue-num 0

snort
# Step 2: Custom inline drop signature (/etc/snort/rules/local.rules)
drop tcp 10.10.1.2 any -> 172.16.1.2 23 (msg:"[NIPS] Active Telnet Attack Blocked"; sid:1000001; rev:2;)

# Step 3: Launch Snort in inline NIPS mode bound to NFQUEUE 0
sudo snort -c /etc/snort/snort.conf -Q --daq nfq --daq-var queue=0 -A console
* *Technical Verdict:* When 10.10.1.2 initiates a TCP SYN probe to 172.16.1.2:23, Snort triggers [Drop] inline and instructs iptables to discard the packet immediately, ensuring zero-packet-leakage perimeter enforcement.

---

## Defense-in-Depth Hardening Recommendations
* *Legacy Service Retirement:* Decommission vsftpd 2.3.4 and telnetd; enforce SSHv2 with key-based authentication (Ed25519 or RSA >= 3072-bit), PermitRootLogin no, and disabled password authentication.
* *Patch Management:* Upgrade Apache HTTPd, Samba, MySQL, and OpenSSL to supported releases to remediate known RCE, DoS, and TLS downgrade vulnerabilities.
* *Stateful Micro-Segmentation:* Enforce a default-deny FORWARD policy (iptables -P FORWARD DROP) paired with stateful connection tracking (-m state --state ESTABLISHED,RELATED -j ACCEPT) and strict inter-subnet whitelisting.
* *Production Inline IPS Resilience:* Mitigate inline inspection latency and Single Point of Failure (SPOF) risks in enterprise deployments by utilizing fail-open hardware bypass NICs or High Availability (HA) active-passive firewall pairs.

---

## Repository Structure
text
├── docs/
│   └── 2410207_HaTheDuy_ReportLab1-4.pdf   # Full technical report with terminal outputs & packet captures
├── configs/
│   ├── iptables-rules.sh                  # Perimeter filtering & NFQUEUE redirection rules
│   └── local.rules                        # Custom Snort NIDS/NIPS detection & inline drop rules
└── README.md

---
*Author:* Ha The Duy — B.Sc. Student in Cybersecurity, University of Science and Technology of Hanoi (USTH)