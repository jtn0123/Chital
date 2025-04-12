#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PROJECT_NAME="Chital"
SCHEME_NAME="Chital"
BUILD_DIR="build"
# The configuration (Debug/Release) used by xcodebuild when skipping signing
# Check the xcodebuild output if Debug doesn't work (default is often Release, but Debug was used above)
CONFIGURATION="Debug" 
# --- Configuration End ---

# Derived path for the built application
APP_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${PROJECT_NAME}.app"

echo "Building ${PROJECT_NAME} (Scheme: ${SCHEME_NAME}, Configuration: ${CONFIGURATION})..."

# Build the project, skipping code signing and putting derived data in ./build/
xcodebuild build \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME_NAME}" \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

echo "Build successful. Application path: ${APP_PATH}"

echo "Launching ${APP_PATH}..."

# Launch the application
open "${APP_PATH}"

echo "${PROJECT_NAME} launched." 