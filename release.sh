#!/usr/bin/env bash
#
# Global Release Automation Script for Claude Code
# Automates the complete release process using recent changes as context
#
# Usage:
#   ./release.sh patch                     # Auto-detect patch release
#   ./release.sh minor                     # Auto-detect minor release
#   ./release.sh major                     # Auto-detect major release
#   ./release.sh v1.2.3 "Custom message"  # Specific version
#

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="release.sh"
readonly PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Output functions
print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

# Check prerequisites
check_prerequisites() {
    local missing_tools=()

    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    command -v gh >/dev/null 2>&1 || missing_tools+=("gh")

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a git repository"
        exit 1
    fi

    # Check if we have a GitHub remote
    if ! git remote get-url origin >/dev/null 2>&1; then
        print_error "No origin remote found"
        exit 1
    fi
}

# Analyze recent git changes
analyze_recent_changes() {
    print_header "Analyzing Recent Changes"

    # Get recent commits
    print_info "Recent commits:"
    git log --oneline -5 --color=always | sed 's/^/  /'

    # Get current status
    if [[ -n $(git status --porcelain) ]]; then
        print_warning "Working directory has uncommitted changes"
        git status --short | sed 's/^/  /'
        echo
    fi

    # Get recent changes stats
    if git rev-parse HEAD~1 >/dev/null 2>&1; then
        print_info "Recent changes summary:"
        git diff HEAD~1..HEAD --stat | sed 's/^/  /'
    fi
}

# Determine current version
get_current_version() {
    local latest_tag
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
    echo "${latest_tag#v}"  # Remove 'v' prefix if present
}

# Increment version based on type
increment_version() {
    local current_version="$1"
    local release_type="$2"

    # Parse version components
    IFS='.' read -ra VERSION_PARTS <<< "${current_version}"
    local major=${VERSION_PARTS[0]:-0}
    local minor=${VERSION_PARTS[1]:-0}
    local patch=${VERSION_PARTS[2]:-0}

    case "${release_type}" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "${major}.$((minor + 1)).0"
            ;;
        patch)
            echo "${major}.${minor}.$((patch + 1))"
            ;;
        *)
            print_error "Invalid release type: ${release_type}"
            exit 1
            ;;
    esac
}

# Generate release notes from recent commits
generate_release_notes() {
    local release_type="$1"
    local new_version="$2"

    print_info "Generating release notes from recent commits..."

    # Get commits since last tag
    local last_tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    local commit_range
    if [[ -n "${last_tag}" ]]; then
        commit_range="${last_tag}..HEAD"
    else
        commit_range="HEAD~5..HEAD"
    fi

    # Analyze commit messages for features, fixes, etc.
    local commits
    commits=$(git log --pretty=format:"- %s" "${commit_range}" 2>/dev/null || echo "- Initial release")

    # Categorize commits
    local features=""
    local improvements=""
    local fixes=""
    local other=""

    while IFS= read -r commit; do
        local lower_commit=$(echo "$commit" | tr '[:upper:]' '[:lower:]')
        if [[ $lower_commit =~ (feat|feature|add|new) ]]; then
            features="${features}${commit}\n"
        elif [[ $lower_commit =~ (fix|bug|patch|resolve) ]]; then
            fixes="${fixes}${commit}\n"
        elif [[ $lower_commit =~ (improve|enhance|update|optimize|refactor) ]]; then
            improvements="${improvements}${commit}\n"
        else
            other="${other}${commit}\n"
        fi
    done <<< "$commits"

    # Generate release title
    local release_title
    case "${release_type}" in
        major)
            release_title="Major Release v${new_version}"
            ;;
        minor)
            release_title="New Features & Improvements v${new_version}"
            ;;
        patch)
            release_title="Bug Fixes & Improvements v${new_version}"
            ;;
        *)
            release_title="Release v${new_version}"
            ;;
    esac

    # Build release notes
    local notes="# ${release_title}\n\n"

    if [[ -n "${features}" ]]; then
        notes="${notes}## 🚀 New Features\n${features}\n"
    fi

    if [[ -n "${improvements}" ]]; then
        notes="${notes}## 💡 Improvements\n${improvements}\n"
    fi

    if [[ -n "${fixes}" ]]; then
        notes="${notes}## 🐛 Bug Fixes\n${fixes}\n"
    fi

    if [[ -n "${other}" ]]; then
        notes="${notes}## 📝 Other Changes\n${other}\n"
    fi

    # Add installation/usage info if it's a public project
    local repo_url
    repo_url=$(git remote get-url origin | sed 's/\.git$//')

    notes="${notes}---\n\n"
    notes="${notes}**Installation**: See repository README for installation instructions.\n\n"
    notes="${notes}**Full Changelog**: ${repo_url}/compare/$(get_current_version)...v${new_version}"

    echo -e "$notes"
}

# Create and push git tag
create_git_tag() {
    local version="$1"
    local tag="v${version}"

    print_header "Creating Git Tag"

    # Create tag
    git tag "$tag"
    print_success "Created tag: $tag"

    # Push tag
    git push origin "$tag"
    print_success "Pushed tag to origin"
}

# Create GitHub release
create_github_release() {
    local version="$1"
    local title="$2"
    local notes="$3"
    local tag="v${version}"

    print_header "Creating GitHub Release"

    # Create release using gh CLI
    local release_url
    release_url=$(gh release create "$tag" --title "$title" --notes "$notes")

    print_success "Created GitHub release: $release_url"
    echo "$release_url"
}

# Update Homebrew tap (if applicable)
update_homebrew_tap() {
    local version="$1"

    print_header "Checking for Homebrew Tap"

    # Try to detect if there's a Homebrew tap
    local github_user
    github_user=$(git remote get-url origin | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p')

    if [[ -z "$github_user" ]]; then
        print_info "Could not detect GitHub username, skipping Homebrew update"
        return
    fi

    local tap_dir="$HOME/homebrew-tap"
    local formula_name
    formula_name=$(basename "$PROJECT_ROOT")

    if [[ -d "$tap_dir" ]]; then
        print_info "Found potential Homebrew tap directory"

        local formula_file="$tap_dir/Formula/${formula_name}.rb"
        if [[ -f "$formula_file" ]]; then
            print_info "Updating Homebrew formula: $formula_file"

            # Download new tarball and calculate SHA256
            local tarball_url="https://github.com/${github_user}/${formula_name}/archive/v${version}.tar.gz"
            local temp_tarball="/tmp/${formula_name}-v${version}.tar.gz"

            if curl -L "$tarball_url" -o "$temp_tarball" 2>/dev/null; then
                local new_sha256
                new_sha256=$(shasum -a 256 "$temp_tarball" | cut -d' ' -f1)

                # Update formula file
                sed -i.bak \
                    -e "s|archive/v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.tar\.gz|archive/v${version}.tar.gz|g" \
                    -e "s|sha256 \"[^\"]*\"|sha256 \"${new_sha256}\"|g" \
                    "$formula_file"

                # Commit and push changes
                (
                    cd "$tap_dir"
                    git add "Formula/${formula_name}.rb"
                    git commit -m "Update ${formula_name} to v${version}"
                    git push origin main
                )

                print_success "Updated Homebrew formula to v${version}"
                rm -f "$temp_tarball"
            else
                print_warning "Could not download tarball for Homebrew update"
            fi
        else
            print_info "No Homebrew formula found at $formula_file"
        fi
    else
        print_info "No Homebrew tap directory found at $tap_dir"
    fi
}

# Verify release completion
verify_release() {
    local version="$1"
    local tag="v${version}"

    print_header "Verifying Release"

    # Check git tag
    if git tag -l | grep -q "^${tag}$"; then
        print_success "Git tag created: $tag"
    else
        print_error "Git tag not found: $tag"
        return 1
    fi

    # Check GitHub release
    if gh release view "$tag" >/dev/null 2>&1; then
        print_success "GitHub release created: $tag"
    else
        print_error "GitHub release not found: $tag"
        return 1
    fi

    print_success "Release verification complete!"
}

# Main function
main() {
    local release_type="${1:-}"
    local custom_message="${2:-}"

    # Show usage if no arguments
    if [[ $# -eq 0 ]]; then
        echo "Usage: $SCRIPT_NAME <patch|minor|major|vX.Y.Z> [custom_message]"
        echo ""
        echo "Examples:"
        echo "  $SCRIPT_NAME patch                     # Auto-detect patch release"
        echo "  $SCRIPT_NAME minor                     # Auto-detect minor release"
        echo "  $SCRIPT_NAME major                     # Auto-detect major release"
        echo "  $SCRIPT_NAME v1.2.3 \"Custom message\"  # Specific version"
        exit 1
    fi

    # Header
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════╗"
    echo "║         Release Automation             ║"
    echo "║      Automated Release Process         ║"
    echo "╚════════════════════════════════════════╝"
    echo -e "${NC}"

    # Check prerequisites
    check_prerequisites

    # Analyze recent changes
    analyze_recent_changes

    # Determine version
    local current_version new_version
    current_version=$(get_current_version)

    if [[ $release_type =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Specific version provided
        new_version="${release_type#v}"  # Remove 'v' prefix
    else
        # Increment based on type
        new_version=$(increment_version "$current_version" "$release_type")
    fi

    print_info "Current version: v$current_version"
    print_info "New version: v$new_version"

    # Generate release notes
    local release_notes
    if [[ -n "$custom_message" ]]; then
        release_notes="$custom_message"
    else
        release_notes=$(generate_release_notes "$release_type" "$new_version")
    fi

    # Extract title from release notes (first line)
    local release_title
    release_title=$(echo -e "$release_notes" | head -1 | sed 's/^# //')

    print_info "Release title: $release_title"

    # Create git tag
    create_git_tag "$new_version"

    # Create GitHub release
    local release_url
    release_url=$(create_github_release "$new_version" "$release_title" "$release_notes")

    # Update Homebrew tap (if applicable)
    update_homebrew_tap "$new_version"

    # Verify release
    verify_release "$new_version"

    # Success message
    echo -e "\n${GREEN}${BOLD}🎉 Release Complete!${NC}"
    echo -e "${GREEN}Version: v${new_version}${NC}"
    echo -e "${GREEN}GitHub Release: ${release_url}${NC}"

    if command -v brew >/dev/null 2>&1; then
        local github_user formula_name
        github_user=$(git remote get-url origin | sed -n 's|.*github\.com[:/]\([^/]*\)/.*|\1|p')
        formula_name=$(basename "$PROJECT_ROOT")

        if [[ -n "$github_user" ]]; then
            echo -e "${BLUE}Homebrew Install: brew install ${github_user}/tap/${formula_name}${NC}"
        fi
    fi
}

# Run main function with all arguments
main "$@"