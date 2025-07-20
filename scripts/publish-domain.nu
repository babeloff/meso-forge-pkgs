#!/usr/bin/env nu

# Script to push a domain branch to remote and remove the worktree on success
# Usage: nu scripts/publish-domain.nu <domain-name>

def main [
    domain_name: string                # Domain name for the packages (required)
] {
    let branch_name = $"pkgs/($domain_name)"
    let worktree_path = $"../meso-forge-pkgs-($domain_name)"

    print $"Publishing domain branch: ($branch_name)"
    print $"Worktree path: ($worktree_path)"
    print ""

    # Check if we're in a git repository
    try {
        ^git rev-parse --git-dir | ignore
    } catch {
        error make {msg: "Not in a git repository"}
    }

    # Check if worktree path exists
    if not ($worktree_path | path exists) {
        error make {msg: $"Worktree directory '($worktree_path)' does not exist"}
    }

    # Check if branch exists
    let branch_exists = try {
        ^git show-ref --verify --quiet $"refs/heads/($branch_name)"
        true
    } catch {
        false
    }

    if not $branch_exists {
        error make {msg: $"Branch '($branch_name)' does not exist"}
    }

    # Store original directory
    let original_dir = (pwd)

    # Change to worktree directory and push
    print $"Pushing branch '($branch_name)' to remote..."
    cd $worktree_path

    try {
        ^git push -u origin $branch_name
        print $"✅ Successfully pushed ($branch_name)"
    } catch {
        cd $original_dir
        error make {msg: $"❌ Failed to push ($branch_name)"}
    }

    # Return to original directory
    cd $original_dir

    # Remove worktree on successful push
    print $"Removing worktree '($worktree_path)'..."
    try {
        ^git worktree remove $worktree_path
        print $"✅ Worktree removed successfully"
    } catch {
        print $"⚠️  Warning: Failed to remove worktree '($worktree_path)'"
        print "You may need to remove it manually with:"
        print $"   git worktree remove ($worktree_path)"
    }

    print ""
    print $"✅ Domain '($domain_name)' published successfully!"
    print $"🌐 Branch '($branch_name)' is now available on remote"
    print ""
    print "To continue working on this domain, create a new worktree:"
    print $"   git worktree add ($worktree_path) ($branch_name)"
}
