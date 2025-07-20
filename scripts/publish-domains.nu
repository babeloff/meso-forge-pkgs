#!/usr/bin/env nu

# Script to publish domain branches to remote and remove worktrees on success
# Usage:
#   nu scripts/publish-domains.nu                    # Publish all domain worktrees
#   nu scripts/publish-domains.nu --domain <name>   # Publish specific domain
#   nu scripts/publish-domains.nu --dry-run         # Show what would be published

def main [
    --domain: string,                  # Specific domain name to publish (optional)
    --dry-run                          # Show what would be published without actually doing it
] {
    if $domain != null {
        print $"🎯 Publishing specific domain: ($domain)"
    } else {
        print "🔍 Discovering all domain worktrees..."
    }
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
    let all_domain_worktrees = ($worktrees
        | where branch != null
        | where ($it.branch | str starts-with "pkgs/")
    )

    # Filter to specific domain if requested
    let domain_worktrees = if $domain != null {
        let target_branch = $"pkgs/($domain)"
        let filtered = ($all_domain_worktrees | where branch == $target_branch)

        if ($filtered | length) == 0 {
            # Check if domain exists as a branch but no worktree
            let branch_exists = try {
                ^git show-ref --verify --quiet $"refs/heads/($target_branch)"
                true
            } catch {
                false
            }

            if $branch_exists {
                error make {msg: $"Domain '($domain)' exists but has no active worktree. Create one with: git worktree add ../meso-forge-pkgs-($domain) ($target_branch)"}
            } else {
                error make {msg: $"Domain '($domain)' not found. Available domains: (($all_domain_worktrees | get branch | str join ', '))"}
            }
        }

        $filtered
    } else {
        $all_domain_worktrees
    }

    if ($domain_worktrees | length) == 0 {
        if $domain != null {
            print $"📭 No worktree found for domain '($domain)'"
        } else {
            print "📭 No domain worktrees found (branches starting with 'pkgs/')"
        }
        return
    }

    let domain_count = ($domain_worktrees | length)
    if $domain != null {
        print $"📦 Found domain worktree: ($domain_worktrees.0.branch) → ($domain_worktrees.0.path)"
    } else {
        print $"📦 Found ($domain_count) domain worktrees:"
        for worktree in $domain_worktrees {
            print $"  • ($worktree.branch) → ($worktree.path)"
        }
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
            # Change to worktree directory, commit pending work, and push
            let push_result = try {
                cd $worktree.path

                # Check for any uncommitted changes
                let has_changes = try {
                    ^git diff-index --quiet HEAD
                    false
                } catch {
                    true
                }

                let has_untracked = try {
                    let untracked_files = (^git ls-files --others --exclude-standard | str trim)
                    ($untracked_files | str length) > 0
                } catch {
                    false
                }

                if $has_changes or $has_untracked {
                    print $"  📝 Found pending changes, committing..."

                    # Add all changes
                    ^git add -A

                    # Create commit message with timestamp
                    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")
                    let commit_message = $"Update ($domain_name) domain - ($timestamp)

Auto-committed pending changes before publishing"

                    try {
                        ^git commit --no-gpg-sign -m $commit_message
                        print $"  ✅ Committed pending changes"
                    } catch {
                        print $"  ⚠️  Warning: Failed to commit changes, continuing with push..."
                    }
                } else {
                    print $"  ✨ No pending changes to commit"
                }

                # Push to remote
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
    if $domain != null {
        if $published_count > 0 {
            print $"✅ Domain '($domain)' published successfully!"
            print $"🌐 Branch 'pkgs/($domain)' is now available on remote"
            print ""
            print "To continue working on this domain, create a new worktree:"
            print $"   git worktree add ../meso-forge-pkgs-($domain) pkgs/($domain)"
        } else {
            print $"❌ Failed to publish domain '($domain)'"
        }
    } else {
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
    }

    if $failed_count > 0 {
        exit 1
    }
}
