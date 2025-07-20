#!/usr/bin/env nu

# Script to publish all domain branches to remote and remove their worktrees on success
# Usage: nu scripts/publish-domains.nu [--dry-run]

def main [
    --dry-run                          # Show what would be published without actually doing it
] {
    print "🔍 Discovering domain worktrees..."
    print ""

    # Check if we're in a git repository
    try {
        ^git rev-parse --git-dir | ignore
    } catch {
        error make {msg: "Not in a git repository"}
    }

    # Get worktree information in porcelain format
    let worktree_output = try {
        ^git worktree list --porcelain | str trim
    } catch {
        error make {msg: "Failed to get worktree list"}
    }

    # Parse the porcelain output to extract worktree info
    let worktrees = ($worktree_output
        | split row "\n\n"
        | each { |block|
            let lines = ($block | split row "\n")
            let worktree_path = ($lines.0 | str replace "worktree " "")
            let head = ($lines.1 | str replace "HEAD " "")

            # Check if there's a branch line
            let branch_line = ($lines | where $it starts-with "branch ")
            if ($branch_line | length) > 0 {
                let branch_ref = ($branch_line.0 | str replace "branch refs/heads/" "")
                {
                    path: $worktree_path,
                    head: $head,
                    branch: $branch_ref
                }
            } else {
                {
                    path: $worktree_path,
                    head: $head,
                    branch: null
                }
            }
        }
    )

    # Filter for domain branches (pkgs/*)
    let domain_worktrees = ($worktrees
        | where branch != null
        | where ($it.branch | str starts-with "pkgs/")
    )

    if ($domain_worktrees | length) == 0 {
        print "📭 No domain worktrees found (branches starting with 'pkgs/')"
        return
    }

    let domain_count = ($domain_worktrees | length)
    print $"📦 Found ($domain_count) domain worktrees:"
    for worktree in $domain_worktrees {
        print $"  • ($worktree.branch) → ($worktree.path)"
    }
    print ""

    if $dry_run {
        print "🔍 DRY RUN MODE - Would publish the following:"
        for worktree in $domain_worktrees {
            let domain_name = ($worktree.branch | str replace "pkgs/" "")
            print $"  📤 ($worktree.branch) from ($worktree.path)"
        }
        print ""
        print "To actually publish, run without --dry-run flag"
        return
    }

    # Store original directory
    let original_dir = (pwd)

    # Process each domain worktree and collect results
    let results = ($domain_worktrees | each { |worktree|
        let domain_name = ($worktree.branch | str replace "pkgs/" "")
        print $"📤 Publishing ($worktree.branch)..."

        # Check if worktree path still exists
        if not ($worktree.path | path exists) {
            print $"  ⚠️  Warning: Worktree path ($worktree.path) no longer exists, skipping"
            { success: false, reason: "path_missing" }
        } else {
            # Change to worktree directory and push
            let push_result = try {
                cd $worktree.path
                ^git push -u origin $worktree.branch
                cd $original_dir
                true
            } catch {
                cd $original_dir
                false
            }

            if $push_result {
                print $"  ✅ Successfully pushed ($worktree.branch)"

                # Remove worktree on successful push
                let remove_result = try {
                    ^git worktree remove $worktree.path
                    print $"  🗑️  Worktree removed: ($worktree.path)"
                    true
                } catch {
                    print $"  ⚠️  Warning: Failed to remove worktree ($worktree.path)"
                    print $"     You may need to remove it manually: git worktree remove ($worktree.path)"
                    true  # Still count as success since push succeeded
                }

                { success: true, reason: "published" }
            } else {
                print $"  ❌ Failed to push ($worktree.branch)"
                { success: false, reason: "push_failed" }
            }
        }
    })

    print ""

    # Calculate summary statistics
    let total_count = ($domain_worktrees | length)
    let published_count = ($results | where success == true | length)
    let failed_count = ($results | where success == false | length)

    # Summary
    print "📊 Publishing Summary:"
    print $"  ✅ Successfully published: ($published_count)/($total_count)"
    if $failed_count > 0 {
        print $"  ❌ Failed to publish: ($failed_count)/($total_count)"
    }
    print ""

    if $published_count > 0 {
        print "🌐 Published branches are now available on remote"
        print ""
        print "To continue working on any domain, create a new worktree:"
        for worktree in $domain_worktrees {
            if ($worktree.path | path exists) == false {
                let domain_name = ($worktree.branch | str replace "pkgs/" "")
                print $"   git worktree add ../meso-forge-pkgs-($domain_name) ($worktree.branch)"
            }
        }
    }

    if $failed_count > 0 {
        exit 1
    }
}
