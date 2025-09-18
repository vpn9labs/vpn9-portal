#!/bin/bash

# SEO Testing Script for VPN9 Portal
# Tests robots.txt, canonical URLs, and redirect headers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BASE_URL="${1:-http://localhost:3000}"

echo "Testing SEO configuration for: $BASE_URL"
echo "========================================="

# Function to check HTTP headers
check_headers() {
  local url=$1
  local expected_header=$2

  echo -n "Checking $url for $expected_header... "

  headers=$(curl -sI "$url")
  if echo "$headers" | grep -q "$expected_header"; then
    echo -e "${GREEN}✓${NC} Found"
    echo "$headers" | grep "$expected_header"
  else
    echo -e "${YELLOW}⚠${NC} Not found"
  fi
  echo
}

# Function to check canonical URL in HTML
check_canonical() {
  local url=$1
  local expected_canonical=$2

  echo -n "Checking canonical URL at $url... "

  html=$(curl -s "$url")
  canonical=$(echo "$html" | grep -o '<link rel="canonical" href="[^"]*"' | sed 's/.*href="\([^"]*\)".*/\1/')

  if [ "$canonical" = "$expected_canonical" ]; then
    echo -e "${GREEN}✓${NC} Correct: $canonical"
  else
    echo -e "${RED}✗${NC} Expected: $expected_canonical, Got: $canonical"
  fi
  echo
}

# Function to check robots meta tag
check_robots_meta() {
  local url=$1
  local expected_robots=$2

  echo -n "Checking robots meta at $url... "

  html=$(curl -s "$url")
  robots=$(echo "$html" | grep -o '<meta name="robots" content="[^"]*"' | sed 's/.*content="\([^"]*\)".*/\1/')

  if echo "$robots" | grep -q "$expected_robots"; then
    echo -e "${GREEN}✓${NC} Found: $robots"
  else
    echo -e "${YELLOW}⚠${NC} Expected to contain '$expected_robots', Got: $robots"
  fi
  echo
}

echo "1. Testing robots.txt"
echo "---------------------"
curl -s "$BASE_URL/robots.txt" | head -20
echo

echo "2. Testing Canonical URLs"
echo "-------------------------"
check_canonical "$BASE_URL" "https://vpn9.com/"
check_canonical "$BASE_URL?live=true" "https://vpn9.com/"
check_canonical "$BASE_URL?cro=true" "https://vpn9.com/"
check_canonical "$BASE_URL?teaser=true" "https://vpn9.com/"

echo "3. Testing Redirect Headers"
echo "---------------------------"
check_headers "$BASE_URL/affiliates" "X-Robots-Tag"

echo "4. Testing Robots Meta Tags"
echo "----------------------------"
check_robots_meta "$BASE_URL/login" "noindex"
check_robots_meta "$BASE_URL/signup" "noindex"
check_robots_meta "$BASE_URL" "index"
check_robots_meta "$BASE_URL/affiliates/login" "index"
check_robots_meta "$BASE_URL/affiliates/new" "index"
echo "Note: Affiliate login and signup should be indexable for discoverability"

echo "5. Testing Sitemap"
echo "------------------"
echo -n "Checking sitemap accessibility... "
status_code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/sitemap.xml")
if [ "$status_code" = "200" ]; then
  echo -e "${GREEN}✓${NC} Accessible (HTTP $status_code)"

  # Count URLs in sitemap
  url_count=$(curl -s "$BASE_URL/sitemap.xml" | grep -c "<loc>" || true)
  echo "Found $url_count URLs in sitemap"

  # Show first few URLs
  echo "Sample URLs:"
  curl -s "$BASE_URL/sitemap.xml" | grep "<loc>" | head -5 | sed 's/.*<loc>\(.*\)<\/loc>.*/  - \1/'
else
  echo -e "${RED}✗${NC} Not accessible (HTTP $status_code)"
fi

echo
echo "========================================="
echo "SEO testing complete!"
echo
echo "Next steps:"
echo "1. Submit updated sitemap to Google Search Console"
echo "2. Use URL Inspection tool to test individual pages"
echo "3. Request validation for fixed issues in Coverage report"
echo "4. Monitor indexing status over the next 1-2 weeks"
