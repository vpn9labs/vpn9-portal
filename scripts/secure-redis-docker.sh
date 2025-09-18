#!/bin/bash
# Script to secure Redis when running in Docker
# Run this on the host server (91.99.104.217)

echo "Setting up firewall rules for Redis (Docker-aware)..."

# First, check current rules
echo "Current iptables rules for port 6379:"
iptables -L -n | grep 6379
echo ""

# Method 1: Use DOCKER-USER chain (recommended for Docker)
echo "Adding rules to DOCKER-USER chain..."
# Clear any existing Redis rules in DOCKER-USER
iptables -D DOCKER-USER -p tcp --dport 6379 -j DROP 2>/dev/null
iptables -D DOCKER-USER -p tcp --dport 6379 -s 10.0.0.0/24 -j ACCEPT 2>/dev/null
iptables -D DOCKER-USER -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT 2>/dev/null

# Add new rules to DOCKER-USER chain (processed before Docker's rules)
iptables -I DOCKER-USER -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 6379 -s 10.0.0.0/24 -j ACCEPT
iptables -I DOCKER-USER -p tcp --dport 6379 -j DROP

# Method 2: Insert at the beginning of INPUT chain (fallback)
echo "Also inserting rules at beginning of INPUT chain..."
# Remove old appended rules if they exist
iptables -D INPUT -p tcp --dport 6379 -j DROP 2>/dev/null
iptables -D INPUT -p tcp --dport 6379 -s 10.0.0.0/24 -j ACCEPT 2>/dev/null
iptables -D INPUT -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT 2>/dev/null

# Insert new rules at the beginning
iptables -I INPUT 1 -p tcp --dport 6379 -j DROP
iptables -I INPUT 1 -p tcp --dport 6379 -s 10.0.0.0/24 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 6379 -s 127.0.0.1 -j ACCEPT

# Save the rules
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save
    echo "Rules saved with netfilter-persistent"
elif command -v iptables-save &> /dev/null; then
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo "Rules saved to /etc/iptables/rules.v4"
fi

echo ""
echo "Firewall rules applied successfully!"
echo ""
echo "New iptables rules for Redis:"
echo "=== DOCKER-USER chain ==="
iptables -L DOCKER-USER -n | grep 6379
echo ""
echo "=== INPUT chain (first 5 rules) ==="
iptables -L INPUT -n | head -n 7
echo ""
echo "Test the configuration:"
echo "  - From localhost: redis-cli -h 127.0.0.1 ping"
echo "  - From private network: redis-cli -h 10.0.0.4 ping"
echo "  - From public IP (should fail): redis-cli -h 91.99.104.217 ping"
