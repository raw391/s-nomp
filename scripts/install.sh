#!/bin/bash
# s-nomp complete installation script
# Handles dependency checking, npm installation, native module building, and patching

set -e  # Exit on error

echo "========================================="
echo "s-nomp Installation Script"
echo "========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ]; then
    echo "Error: Must be run from s-nomp root directory"
    exit 1
fi

# Check Node.js version
echo "Checking Node.js version..."
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 20 ]; then
    echo "❌ Error: Node.js 20.x or higher is required"
    echo "   Current version: $(node -v)"
    echo "   Install with: sudo npm install n -g && sudo n stable"
    exit 1
fi
echo "✓ Node.js $(node -v) detected"
echo ""

# Check Redis
echo "Checking Redis..."
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        echo "✓ Redis is running"
    else
        echo "⚠ Redis is installed but not running"
        echo "   Start with: sudo systemctl start redis-server"
    fi
else
    echo "⚠ Redis not found"
    echo "   Install with: sudo apt-get install redis-server"
fi
echo ""

# Check build dependencies
echo "Checking build dependencies..."
MISSING_DEPS=0

if ! command -v gcc &> /dev/null; then
    echo "❌ gcc not found (install with: sudo apt-get install build-essential)"
    MISSING_DEPS=1
fi

if ! command -v make &> /dev/null; then
    echo "❌ make not found (install with: sudo apt-get install build-essential)"
    MISSING_DEPS=1
fi

if ! dpkg -l | grep -q libsodium-dev; then
    echo "⚠ libsodium-dev not found (install with: sudo apt-get install libsodium-dev)"
fi

if ! dpkg -l | grep -q libboost-all-dev; then
    echo "⚠ libboost-all-dev not found (install with: sudo apt-get install libboost-all-dev)"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo "❌ Missing required build tools. Install with:"
    echo "   sudo apt-get install build-essential libsodium-dev libboost-all-dev"
    exit 1
fi
echo "✓ Build dependencies found"
echo ""

# Install npm dependencies
echo "Step 1: Installing npm dependencies..."
echo "---------------------------------------"
if [ ! -d "node_modules" ]; then
    echo "Running npm update..."
    npm update
fi

echo "Running npm install..."
npm install --legacy-peer-deps --ignore-scripts
echo "✓ npm dependencies installed"
echo ""

# Build native modules
echo "Step 2: Building native modules..."
echo "-----------------------------------"

if [ -d "node_modules/equihashverify" ]; then
    echo "Building equihashverify..."
    cd node_modules/equihashverify
    ../../node_modules/.bin/node-gyp rebuild
    cd ../..
    echo "✓ equihashverify built successfully"
else
    echo "❌ equihashverify not found in node_modules"
    exit 1
fi

if [ -d "node_modules/bignum" ]; then
    echo "Building bignum..."
    cd node_modules/bignum
    ../../node_modules/.bin/node-gyp rebuild
    cd ../..
    echo "✓ bignum built successfully"
else
    echo "❌ bignum not found in node_modules"
    exit 1
fi

echo ""

# Patch jobManager.js
echo "Step 3: Patching jobManager.js..."
echo "----------------------------------"

JOBMANAGER="node_modules/stratum-pool/lib/jobManager.js"

if [ ! -f "$JOBMANAGER" ]; then
    echo "❌ $JOBMANAGER not found"
    exit 1
fi

# Check if already patched
if grep -q "lazy load verushash" "$JOBMANAGER"; then
    echo "✓ jobManager.js already patched"
else
    echo "Patching jobManager.js to make verushash optional..."

    # Create backup
    cp "$JOBMANAGER" "$JOBMANAGER.backup"

    # Patch line 9: require('verushash') -> null with comment
    sed -i "s/var vh = require('verushash');/var vh = null; \/\/ lazy load verushash only when needed/" "$JOBMANAGER"

    # Patch the verushash case to add lazy loading
    # Find the line with "headerHash = vh.hash(headerSolnBuffer);" and add the if statement before it
    sed -i "/case 'verushash':/,/break;/ {
        /headerHash = vh\.hash(headerSolnBuffer);/ {
            i\                if (!vh) vh = require('verushash'); // lazy load only when needed
        }
    }" "$JOBMANAGER"

    # Verify patch was applied
    if grep -q "lazy load verushash" "$JOBMANAGER"; then
        echo "✓ jobManager.js patched successfully (backup saved as $JOBMANAGER.backup)"
    else
        echo "❌ Failed to patch jobManager.js"
        mv "$JOBMANAGER.backup" "$JOBMANAGER"
        exit 1
    fi
fi

echo ""

# Check PM2
echo "Step 4: Checking PM2..."
echo "-----------------------"
if command -v pm2 &> /dev/null; then
    echo "✓ PM2 is installed (version $(pm2 -v))"
else
    echo "⚠ PM2 not found (recommended for production)"
    echo "   Install with: sudo npm install pm2 -g"
fi

echo ""
echo "========================================="
echo "✓ Installation Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Configure the pool:"
echo "   cp config_example.json config.json"
echo "   # Edit config.json with your Redis settings"
echo ""
echo "2. Configure your coin:"
echo "   # Create pool_configs/yourcoin.json"
echo "   # See examples in pool_configs/ directory"
echo "   # Configure: address, daemon settings, ports, etc."
echo ""
echo "3. Start your coin daemon:"
echo "   # Make sure your coin daemon is running and synced"
echo "   # Example: zerod -daemon"
echo ""
echo "4. Start the pool:"
echo "   pm2 start ecosystem.config.js"
echo "   pm2 save"
echo "   pm2 logs s-nomp"
echo ""
echo "   Or for development/testing:"
echo "   npm start"
echo ""
