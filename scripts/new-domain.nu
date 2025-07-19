#!/usr/bin/env nu

# Script to create a new orphan branch with template files
# Usage: nu scripts/new-domain.nu <domain-name> [content-description] [list-of-packages]

def main [
    domain_name: string,               # Domain name for the packages (required)
    content_description?: string,      # Content description (defaults to "domain-specific")
    list_of_packages?: string          # List of packages (defaults to "TBD")
] {
    let branch_name = $"pkgs/($domain_name)"
    let content_desc = ($content_description | default "domain-specific")
    let package_list = ($list_of_packages | default "TBD")

    print $"Creating new orphan branch: ($branch_name)"
    print $"Domain name: ($domain_name)"
    print $"Content description: ($content_desc)"
    print $"Package list: ($package_list)"
    print ""

    # Check if we're in a git repository
    try {
        ^git rev-parse --git-dir | ignore
    } catch {
        error make {msg: "Not in a git repository"}
    }

    # Check if branch already exists
    let branch_exists = try {
        ^git show-ref --verify --quiet $"refs/heads/($branch_name)"
        true
    } catch {
        false
    }

    if $branch_exists {
        error make {msg: $"Branch '($branch_name)' already exists"}
    }

    # Store current branch to potentially return to it
    let current_branch = try {
        ^git rev-parse --abbrev-ref HEAD | str trim
    } catch {
        "HEAD"
    }

    # Create new orphan branch
    print $"Creating orphan branch '($branch_name)'..."
    ^git checkout --orphan $branch_name

    # Remove all files from the working directory
    print "Cleaning working directory..."
    try { ^git rm -rf . } catch { }

    # Remove hidden files and directories (except .git)
    ls -a
    | where name != ".git" and name != "." and name != ".."
    | each { |file| rm -rf $file.name }

    # Check if templates directory exists and extract it if needed
    let templates_exist = try {
        ^git show ($current_branch + ":templates/") | ignore
        true
    } catch {
        false
    }

    if not $templates_exist {
        print "Warning: No templates directory found in the current branch"
        print "Checking out templates from management branch..."

        # Try to get templates from management branch
        let management_exists = try {
            ^git show-ref --verify --quiet "refs/heads/management"
            true
        } catch {
            false
        }

        if $management_exists {
            print "Found management branch, extracting templates..."
            try { ^git checkout management -- templates/ } catch { }
        } else {
            print "Warning: No management branch found, checking main/master..."
            for branch in ["main", "master"] {
                let branch_exists = try {
                    ^git show-ref --verify --quiet $"refs/heads/($branch)"
                    true
                } catch {
                    false
                }

                if $branch_exists {
                    print $"Found ($branch) branch, extracting templates..."
                    try { ^git checkout $branch -- templates/ } catch { }
                    break
                }
            }
        }
    } else {
        # Extract templates from current branch
        try { ^git checkout $current_branch -- templates/ } catch { }
    }

    # Process template files
    print "Processing template files..."
    let template_count = if ("templates" | path exists) {
        ls templates/*.template
        | each { |file|
            let target_file = ($file.name | path basename | str replace ".template" "")
            print $"  Processing: ($file.name) -> ($target_file)"

            # Read template file and process variables
            open $file.name
            | str replace -a "<< domain-name >>" $domain_name
            | str replace -a "<< content-description >>" $content_desc
            | str replace -a "<< list-of-packages >>" $package_list
            | save $target_file

            ^git add $target_file
        }
        | length

        # Clean up the templates directory since we don't want it in the new branch
        rm -rf templates/
    } else {
        print "Warning: No templates directory found"
        0
    }

    # Create pkgs directory
    print "Creating pkgs directory..."
    mkdir pkgs
    $"# Packages directory for ($domain_name)" | save pkgs/.gitkeep
    ^git add pkgs/.gitkeep

    # Make initial commit
    print "Making initial commit..."
    let commit_message = $"Initial commit for ($branch_name) branch

- Added ($template_count) template files
- Created pkgs/ directory
- Domain: ($domain_name)
- Description: ($content_desc)"

    ^git commit -m $commit_message

    print ""
    print $"✅ Successfully created orphan branch: ($branch_name)"
    print $"📁 Added template files: ($template_count)"
    print "📦 Created pkgs/ directory"
    print ""
    print "Branch is now active. To return to previous branch, run:"
    print $"   git checkout ($current_branch)"
    print ""
    print "To push this new branch to remote, run:"
    print $"   git push -u origin ($branch_name)"
}
