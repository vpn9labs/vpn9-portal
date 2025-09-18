#!/bin/bash
# Script to secure Redis with firewall rules
# Run this on the host server (91.99.104.217)

echo "Setting up firewall rules for Redis..."

# Allow Redis connections from localhost
iptables -A INPUT -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT

# Allow Redis connections from the private network (adjust subnet as needed)
iptables -A INPUT -p tcp --dport 6379 -s 10.0.0.0/24 -j ACCEPT

# Drop all other connections to Redis
iptables -A INPUT -p tcp --dport 6379 -j DROP

# Save the rules (Ubuntu/Debian)
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
    echo "Rules saved with netfilter-persistent"
elif command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4
    echo "Rules saved to /etc/iptables/rules.v4"
fi

echo "Firewall rules applied successfully!"
echo ""
echo "Current Redis port rules:"
iptables -L INPUT -n | grep 6379
