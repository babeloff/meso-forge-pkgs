#!/usr/bin/env nu

# Script to create a new orphan branch with template files using Git worktrees
# Usage: nu scripts/new-domain.nu <domain-name> [content-description] [list-of-packages]

def main [
    domain_name: string,               # Domain name for the packages (required)
    content_description?: string,      # Content description (defaults to "domain-specific")
    list_of_packages?: string          # List of packages (defaults to "TBD")
] {
    let branch_name = $"pkgs/($domain_name)"
    let content_desc = ($content_description | default "domain-specific")
    let package_list = ($list_of_packages | default "TBD")
    let worktree_path = $"../meso-forge-pkgs-($domain_name)"

    print $"Creating new orphan branch: ($branch_name)"
    print $"Domain name: ($domain_name)"
    print $"Content description: ($content_desc)"
    print $"Package list: ($package_list)"
    print $"Worktree path: ($worktree_path)"
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

    # Check if worktree path already exists
    if ($worktree_path | path exists) {
        error make {msg: $"Worktree directory '($worktree_path)' already exists"}
    }

    # Get current branch for template extraction
    let current_branch = try {
        ^git rev-parse --abbrev-ref HEAD | str trim
    } catch {
        "HEAD"
    }

    # Store original directory
    let original_dir = (pwd)

    # Create new orphan branch in a worktree
    print $"Creating orphan branch '($branch_name)' in worktree '($worktree_path)'..."
    ^git worktree add --orphan $worktree_path $branch_name

    # Check if templates directory exists in the current branch
    let templates_exist = try {
        ^git show $"($current_branch):templates/" | ignore
        true
    } catch {
        false
    }

    mut template_branch = $current_branch
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
            $template_branch = "management"
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
                    $template_branch = $branch
                    break
                }
            }
        }
    }

    # Extract templates to temporary directory
    print "Extracting template files..."
    let temp_dir = (^mktemp -d | str trim)
    try {
        ^git archive $template_branch templates/ | ^tar -x -C $temp_dir
    } catch {
        print "Error: Could not extract templates"
        # Clean up worktree on error
        ^git worktree remove $worktree_path --force
        error make {msg: "Failed to extract template files"}
    }

    # Change to worktree directory for the rest of the operations
    cd $worktree_path

    # Process template files
    print "Processing template files..."
    let template_files_path = ($temp_dir | path join "templates")
    let template_count = if ($template_files_path | path exists) {
        let template_files = try {
            ls ($template_files_path | path join "*.template")
        } catch {
            []
        }

        for file in $template_files {
            let target_file = ($file.name | path basename | str replace ".template" "")
            print $"  Processing: ($file.name | path basename) -> ($target_file)"

            # Read template file and process variables
            let processed_content = (
                open $file.name
                | str replace -a "<< domain-name >>" $domain_name
                | str replace -a "<< content-description >>" $content_desc
                | str replace -a "<< list-of-packages >>" $package_list
            )

            $processed_content | save $target_file
            ^git add $target_file
        }

        ($template_files | length)
    } else {
        print "Warning: No templates directory found"
        0
    }

    # Clean up temporary directory
    rm -rf $temp_dir

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

    # Return to original directory
    cd $original_dir

    print ""
    print $"✅ Successfully created orphan branch: ($branch_name)"
    print $"📁 Worktree location: ($worktree_path)"
    print $"📄 Added template files: ($template_count)"
    print "📦 Created pkgs/ directory"
    print ""
    print "To work on this branch:"
    print $"   cd ($worktree_path)"
    print ""
    print "To push this new branch to remote:"
    print $"   cd ($worktree_path) && git push -u origin ($branch_name)"
    print ""
    print "To remove the worktree when done:"
    print $"   git worktree remove ($worktree_path)"
    print "   git branch -d ($branch_name)  # if you want to delete the branch too"
}
