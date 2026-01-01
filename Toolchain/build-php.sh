#!/bin/bash

# PHP-iOS Build Script
# Cross-compiles PHP 8.3+ static library for arm64-apple-ios

set -e

# Configuration
PHP_VERSION="8.4.16"
MIN_IOS_VERSION="16.0"
EXTENSIONS="json,mbstring,pcre,ctype,filter,tokenizer,xml,dom,libzip"
SDK_NAME="iphoneos"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
INSTALL_DIR=""
SDK_DIR=""
SDK_PATH=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --php=*)
            PHP_VERSION="${1#*=}"
            shift
            ;;
        --extensions=*)
            EXTENSIONS="${1#*=}"
            shift
            ;;
        --min-ios=*)
            MIN_IOS_VERSION="${1#*=}"
            shift
            ;;
        --sdk=*)
            SDK_NAME="${1#*=}"
            shift
            ;;
        --sim)
            SDK_NAME="iphonesimulator"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --php=VERSION        PHP version (default: 8.4.16)"
            echo "  --extensions=LIST    Comma-separated list of extensions (default: json,mbstring,pcre,ctype,filter,tokenizer,xml,dom,libzip)"
            echo "  --min-ios=VERSION    Minimum iOS version (default: 16.0)"
            echo "  --sdk=SDK            SDK name (iphoneos or iphonesimulator, default: iphoneos)"
            echo "  --sim                Shortcut for --sdk=iphonesimulator"
            echo "  --help               Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ "$SDK_NAME" != "iphoneos" ] && [ "$SDK_NAME" != "iphonesimulator" ]; then
    log_error "Unsupported SDK: $SDK_NAME (use iphoneos or iphonesimulator)"
    exit 1
fi

if [ "$SDK_NAME" = "iphonesimulator" ]; then
    INSTALL_DIR="$ROOT_DIR/Sources/PhpIOS/lib-sim"
    SDK_DIR="$SCRIPT_DIR/sdk-sim"
else
    INSTALL_DIR="$ROOT_DIR/Sources/PhpIOS/lib"
    SDK_DIR="$SCRIPT_DIR/sdk-device"
fi

log_info "Building PHP $PHP_VERSION for iOS $MIN_IOS_VERSION+ ($SDK_NAME)"
log_info "Extensions: $EXTENSIONS"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for Xcode command line tools
    if ! command -v xcrun &> /dev/null; then
        log_error "Xcode command line tools not found. Please install them first."
        exit 1
    fi
    
    # Check for required tools
    for tool in curl tar make; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool not found. Please install it first."
            exit 1
        fi
    done
    
    log_info "Prerequisites check passed"
}

# Setup iOS SDK
setup_ios_sdk() {
    log_info "Setting up iOS SDK..."
    
    # Get iOS SDK path
    SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)
    if [ -z "$SDK_PATH" ]; then
        log_error "iOS SDK not found"
        exit 1
    fi
    
    log_info "iOS SDK found at: $SDK_PATH"
    
    # Create SDK directory structure
    mkdir -p "$SDK_DIR"/{include,lib}
    
    # Copy necessary headers and libraries
    cp -r "$SDK_PATH"/usr/include/* "$SDK_DIR/include/" 2>/dev/null || true
    cp -r "$SDK_PATH"/System/Library/Frameworks/*/Headers "$SDK_DIR/include/" 2>/dev/null || true
    
    log_info "iOS SDK setup complete"
}

# Download and extract PHP source
download_php() {
    log_info "Downloading PHP $PHP_VERSION source..."
    
    PHP_URL="https://www.php.net/distributions/php-$PHP_VERSION.tar.gz"
    PHP_TAR="php-$PHP_VERSION.tar.gz"
    
    if [ ! -f "$PHP_TAR" ]; then
        curl -L -o "$PHP_TAR" "$PHP_URL"
    fi
    
    if [ -d "php-$PHP_VERSION" ]; then
        rm -rf "php-$PHP_VERSION"
    fi
    
    tar -xzf "$PHP_TAR"
    log_info "PHP source extracted"
}

# Apply iOS-specific patches
apply_patches() {
    log_info "Applying iOS-specific patches..."
    
    PHP_SRC_DIR="php-$PHP_VERSION"
    
    # Apply patches from patches directory
    if [ -d "patches" ]; then
        for patch in patches/*.patch; do
            if [ -f "$patch" ]; then
                log_info "Applying patch: $(basename "$patch")"
                if ! patch -d "$PHP_SRC_DIR" -p1 --batch --forward < "$patch"; then
                    if patch -d "$PHP_SRC_DIR" -p1 --batch --reverse --dry-run < "$patch" >/dev/null 2>&1; then
                        log_warn "Patch already applied: $(basename "$patch")"
                    else
                        log_error "Patch failed: $(basename "$patch")"
                        exit 1
                    fi
                fi
            fi
        done
    fi
    
    log_info "Patches applied"
}

# Configure PHP build
configure_php() {
    log_info "Configuring PHP build..."
    
    PHP_SRC_DIR="php-$PHP_VERSION"
    cd "$PHP_SRC_DIR"
    
    # Set up iOS toolchain
    export CC="$(xcrun --sdk "$SDK_NAME" --find clang)"
    export CXX="$(xcrun --sdk "$SDK_NAME" --find clang++)"
    if [ "$SDK_NAME" = "iphonesimulator" ]; then
        export CFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-simulator-version-min=$MIN_IOS_VERSION"
    else
        export CFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS_VERSION"
    fi
    export CXXFLAGS="$CFLAGS"
    if [ "$SDK_NAME" = "iphonesimulator" ]; then
        export LDFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-simulator-version-min=$MIN_IOS_VERSION -Wl,-no_warn_duplicate_libraries"
    else
        export LDFLAGS="-arch arm64 -isysroot $SDK_PATH -mios-version-min=$MIN_IOS_VERSION -Wl,-no_warn_duplicate_libraries"
    fi
    export EXTRA_LDFLAGS="-Wl,-no_warn_duplicate_libraries"
    export LIBXML_CFLAGS="-I$SDK_PATH/usr/include/libxml2"
    export LIBXML_LIBS="-lxml2"
    
    # Configure PHP
    ./configure \
        --host=arm64-apple-darwin \
        --target=arm64-apple-darwin \
        --build=x86_64-apple-darwin \
        --prefix="$INSTALL_DIR" \
        --disable-all \
        --enable-cli \
        --enable-embed=static \
        --enable-static \
        --disable-shared \
        --without-iconv \
        --with-libxml \
        --without-openssl \
        --without-zlib \
        --without-bz2 \
        --without-curl \
        --without-gd \
        --without-mysql \
        --without-mysqli \
        --without-pdo-mysql \
        --without-pdo-sqlite \
        --without-sqlite3 \
        --without-xmlrpc \
        --without-xsl \
        --without-readline \
        --without-editline \
        --without-pear \
        --without-gettext \
        --without-libintl \
        --without-gmp \
        --without-bcmath \
        --without-calendar \
        --without-exif \
        --without-ftp \
        --without-imap \
        --without-ldap \
        --without-mcrypt \
        --without-mhash \
        --without-pspell \
        --without-recode \
        --without-snmp \
        --without-sockets \
        --without-sysvmsg \
        --without-sysvsem \
        --without-sysvshm \
        --without-tidy \
        --without-wddx \
        --without-xmlreader \
        --without-xmlwriter \
        --without-xsl \
        --without-zip \
        --enable-json \
        --enable-mbstring \
        --disable-mbregex \
        --enable-pcre \
        --enable-ctype \
        --enable-filter \
        --enable-tokenizer \
        --enable-xml \
        --enable-dom \
        --enable-libzip
    
    cd ..
    log_info "PHP configuration complete"
}

# Build PHP
build_php() {
    log_info "Building PHP..."
    
    PHP_SRC_DIR="php-$PHP_VERSION"
    cd "$PHP_SRC_DIR"
    
    # Build
    make -j$(sysctl -n hw.ncpu)
    
    # Install
    make install
    
    cd ..
    log_info "PHP build complete"
}

# Create static library
create_static_library() {
    log_info "Creating static library..."
    
    # Create lib directory
    mkdir -p "$INSTALL_DIR"
    
    # Copy static library
    PHP_SRC_DIR="php-$PHP_VERSION"
    LIBPHP_CANDIDATES=(
        "$INSTALL_DIR/lib/libphp.a"
        "$PHP_SRC_DIR/libs/libphp.a"
        "$PHP_SRC_DIR/.libs/libphp.a"
        "$PHP_SRC_DIR/sapi/embed/libphp.a"
        "$PHP_SRC_DIR/sapi/embed/.libs/libphp.a"
    )
    LIBPHP_SRC=""
    for candidate in "${LIBPHP_CANDIDATES[@]}"; do
        if [ -f "$candidate" ]; then
            LIBPHP_SRC="$candidate"
            break
        fi
    done

    if [ -z "$LIBPHP_SRC" ]; then
        log_error "libphp.a not found (searched: ${LIBPHP_CANDIDATES[*]})."
        exit 1
    fi

    cp "$LIBPHP_SRC" "$INSTALL_DIR/libphp-ios.a"
    
    # Copy headers
    mkdir -p "$INSTALL_DIR/include"
    cp -r php-$PHP_VERSION/main/*.h "$INSTALL_DIR/include/" 2>/dev/null || true
    cp -r php-$PHP_VERSION/Zend/*.h "$INSTALL_DIR/include/" 2>/dev/null || true
    cp -r php-$PHP_VERSION/TSRM/*.h "$INSTALL_DIR/include/" 2>/dev/null || true
    
    log_info "Static library created at: $INSTALL_DIR/libphp-ios.a"
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    
    if [ -d "php-$PHP_VERSION" ]; then
        rm -rf "php-$PHP_VERSION"
    fi
    
    if [ -f "php-$PHP_VERSION.tar.gz" ]; then
        rm -f "php-$PHP_VERSION.tar.gz"
    fi
    
    log_info "Cleanup complete"
}

# Main execution
main() {
    log_info "Starting PHP-iOS build process..."

    cd "$SCRIPT_DIR"
    check_prerequisites
    setup_ios_sdk
    download_php
    apply_patches
    configure_php
    build_php
    create_static_library
    cleanup
    
    log_info "Build process completed successfully!"
    log_info "Static library: $INSTALL_DIR/libphp-ios.a"
    log_info "Headers: $INSTALL_DIR/include/"
}

# Run main function
main "$@"
