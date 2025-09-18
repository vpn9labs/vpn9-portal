#!/bin/bash
# Generate SSL certificates for Redis
# Run this script on the host server or locally before deployment

set -e

# Configuration
CERT_DIR="/home/aa/Documents/vpn9-portal/config/redis-ssl"
CERT_VALIDITY_DAYS=3650  # 10 years
COUNTRY="US"
STATE="CA"
CITY="San Francisco"
ORGANIZATION="VPN9"
ORGANIZATIONAL_UNIT="Infrastructure"
COMMON_NAME="vpn9-redis"

echo "Creating certificate directory..."
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Generate CA private key
echo "Generating CA private key..."
openssl genrsa -out ca.key 4096

# Generate CA certificate
echo "Generating CA certificate..."
openssl req -new -x509 -days $CERT_VALIDITY_DAYS -key ca.key -out ca.crt -subj \
  "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=$COMMON_NAME-CA"

# Generate server private key
echo "Generating server private key..."
openssl genrsa -out server.key 4096

# Generate server certificate signing request
echo "Generating server certificate signing request..."
openssl req -new -key server.key -out server.csr -subj \
  "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=$COMMON_NAME"

# Create extensions file for server certificate
cat > server-extensions.cnf <<EOF
basicConstraints=CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = vpn9-portal-redis
DNS.3 = redis
DNS.4 = vpn9.com
IP.1 = 127.0.0.1
IP.2 = 91.99.104.217
IP.3 = 10.0.0.4
EOF

# Sign server certificate with CA
echo "Signing server certificate..."
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -days $CERT_VALIDITY_DAYS -extfile server-extensions.cnf

# Generate client private key
echo "Generating client private key..."
openssl genrsa -out client.key 4096

# Generate client certificate signing request
echo "Generating client certificate signing request..."
openssl req -new -key client.key -out client.csr -subj \
  "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORGANIZATION/OU=$ORGANIZATIONAL_UNIT/CN=$COMMON_NAME-client"

# Sign client certificate with CA
echo "Signing client certificate..."
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out client.crt -days $CERT_VALIDITY_DAYS

# Generate Diffie-Hellman parameters (for additional security)
echo "Generating Diffie-Hellman parameters (this may take a while)..."
openssl dhparam -out dh4096.pem 4096

# Set appropriate permissions
chmod 400 *.key
chmod 444 *.crt *.pem

# Clean up CSR files
rm -f *.csr server-extensions.cnf

echo ""
echo "SSL certificates generated successfully!"
echo "Certificate files created in: $CERT_DIR"
echo ""
echo "Files generated:"
echo "  - ca.crt        : Certificate Authority certificate"
echo "  - ca.key        : Certificate Authority private key"
echo "  - server.crt    : Redis server certificate"
echo "  - server.key    : Redis server private key"
echo "  - client.crt    : Redis client certificate"
echo "  - client.key    : Redis client private key"
echo "  - dh4096.pem    : Diffie-Hellman parameters"
echo ""
echo "Next steps:"
echo "1. Copy certificates to the Redis server"
echo "2. Update Redis configuration to use SSL"
echo "3. Update client connections to use SSL"

