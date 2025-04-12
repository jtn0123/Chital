#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PROJECT_NAME="Chital"
SCHEME_NAME="Chital"
BUILD_DIR="build"
# --- Configuration End ---

echo "Cleaning build artifacts for ${PROJECT_NAME} (Scheme: ${SCHEME_NAME})..."

# Clean the build using xcodebuild
xcodebuild clean \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME_NAME}" \
  -derivedDataPath "${BUILD_DIR}"

echo "Xcode clean complete."

# Optional: Uncomment the following lines to remove the entire build directory
# echo "Removing local build directory: ${BUILD_DIR}"
# rm -rf "${BUILD_DIR}"
# echo "Build directory removed."

echo "Cleanup finished." 