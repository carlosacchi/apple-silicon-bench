#!/bin/bash
set -e

# Usage: ./scripts/bump-version.sh <major|minor|patch|x.y.z>
# Examples:
#   ./scripts/bump-version.sh patch    # 1.0.0 -> 1.0.1
#   ./scripts/bump-version.sh minor    # 1.0.0 -> 1.1.0
#   ./scripts/bump-version.sh major    # 1.0.0 -> 2.0.0
#   ./scripts/bump-version.sh 2.0.0    # Set specific version

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

PACKAGE_FILE="$ROOT_DIR/Package.swift"
VERSION_FILE="$ROOT_DIR/Sources/osx-bench/Core/Version.swift"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

# Get current version from Package.swift
CURRENT_VERSION=$(grep 'let version = ' "$PACKAGE_FILE" | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$CURRENT_VERSION" ]; then
    echo "Error: Could not find version in Package.swift"
    exit 1
fi

echo "Current version: $CURRENT_VERSION"

# Parse current version
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Determine new version
case "$1" in
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    minor)
        NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
        ;;
    patch)
        NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
        ;;
    [0-9]*)
        NEW_VERSION="$1"
        ;;
    *)
        echo "Usage: $0 <major|minor|patch|x.y.z>"
        exit 1
        ;;
esac

echo "New version: $NEW_VERSION"

# Update Package.swift
sed -i '' "s/let version = \".*\"/let version = \"$NEW_VERSION\"/" "$PACKAGE_FILE"

# Update Version.swift
sed -i '' "s/static let version = \".*\"/static let version = \"$NEW_VERSION\"/" "$VERSION_FILE"

echo "Updated Package.swift and Version.swift"

# Prompt for changelog entry
read -p "Add changelog entry? (y/n): " ADD_CHANGELOG
if [ "$ADD_CHANGELOG" = "y" ]; then
    TODAY=$(date +%Y-%m-%d)

    # Create temp file with new entry
    cat > /tmp/changelog_entry.md << EOF

## [$NEW_VERSION] - $TODAY

### Changed
-

EOF

    # Insert after first ## line
    sed -i '' "/^## \[/r /tmp/changelog_entry.md" "$CHANGELOG_FILE"
    echo "Added changelog entry template. Please edit CHANGELOG.md"
    ${EDITOR:-vim} "$CHANGELOG_FILE"
fi

# Prompt for git operations
read -p "Commit and tag? (y/n): " DO_GIT
if [ "$DO_GIT" = "y" ]; then
    git add "$PACKAGE_FILE" "$VERSION_FILE" "$CHANGELOG_FILE"
    git commit -m "chore: bump version to $NEW_VERSION"
    git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"

    read -p "Push to origin? (y/n): " DO_PUSH
    if [ "$DO_PUSH" = "y" ]; then
        git push origin main
        git push origin "v$NEW_VERSION"
        echo "Pushed to origin. Release workflow should start."
    fi
fi

echo "Done! Version bumped to $NEW_VERSION"
