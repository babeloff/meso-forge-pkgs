#!/usr/bin/env nu

# Catalog all packages across pkgs/* branches and generate PACKAGES.adoc
# This script uses a temporary worktree to avoid disrupting the current working tree

def main [] {
    print "Starting package catalog generation..."

    # Check if we're in a git repository
    try {
        ^git rev-parse --git-dir | ignore
    } catch {
        error make {msg: "Not in a git repository"}
    }

    # Fetch latest remote information and prune stale branches
    print "Fetching latest remote branch information..."
    try {
        ^git fetch --prune
    } catch {
        print "Warning: Could not fetch remote updates, proceeding with cached branch info"
    }

    let worktree_path = "../meso-forge-pkgs-tmp/catalog"

    print $"Using temporary worktree: ($worktree_path)"

    # Clean up any existing worktree
    if ($worktree_path | path exists) {
        print "Cleaning up existing temporary worktree..."
        try {
            ^git worktree remove $worktree_path --force
        } catch {
            print $"Warning: Could not remove existing worktree, trying to delete directory..."
            rm -rf $worktree_path
        }
    }

    # Store original directory
    let original_dir = (pwd)

    # Create temporary worktree
    print "Creating temporary worktree..."
    try {
        ^git worktree add --detach $worktree_path
    } catch {
        error make {msg: $"Failed to create temporary worktree at ($worktree_path)"}
    }

    # Change to worktree directory
    cd $worktree_path

    # Create/overwrite PACKAGES.adoc with header
    let header = "= Package Catalog - meso-forge

This document lists all packages available across the meso-forge package domains.
Generated automatically by scanning all pkgs/* branches.

"
    $header | save --force PACKAGES.adoc

    # Find all remote branches that match pkgs/*
    let pkg_branches = try {
        ^git branch -r
        | lines
        | where ($it | str contains "origin/pkgs/")
        | where ($it | str contains "HEAD") == false
        | each { |it|
            $it | str trim | str replace "origin/" ""
        }
        | sort
    } catch {
        []
    }

    if ($pkg_branches | is-empty) {
        print "No pkgs/* branches found!"
        cd $original_dir
        ^git worktree remove $worktree_path --force
        return
    }

    print $"Found package branches: ($pkg_branches | str join ', ')"

    # Process each branch
    for branch in $pkg_branches {
        let domain = ($branch | str replace "pkgs/" "")
        print $"Processing branch: ($branch) - domain: ($domain)"

        # Try to checkout the remote branch with force to handle uncommitted files
        let checkout_result = try {
            ^git checkout --force $"origin/($branch)"
            0
        } catch {
            1
        }

        if $checkout_result == 0 {
            $"\n== ($domain) Domain\n" | save --append PACKAGES.adoc

            # Check if pkgs directory exists
            if ("pkgs" | path exists) {
                # List all package directories
                let packages = try {
                    ls pkgs
                    | where type == dir
                    | get name
                    | each { |it| $it | path basename }
                    | sort
                } catch {
                    []
                }

                if not ($packages | is-empty) {
                    for pkg in $packages {
                        let recipe_file = $"pkgs/($pkg)/recipe.yaml"
                        let summary = if ($recipe_file | path exists) {
                            # Try to extract summary from recipe.yaml
                            try {
                                open $recipe_file
                                | lines
                                | where ($it | str contains "summary:")
                                | first
                                | str replace ".*summary:" ""
                                | str trim
                                | str replace "^[\"']" ""
                                | str replace "[\"']$" ""
                            } catch {
                                ""
                            }
                        } else {
                            ""
                        }

                        if ($summary | is-empty) {
                            $"* *($pkg)*\n" | save --append PACKAGES.adoc
                        } else {
                            $"* *($pkg)* - ($summary)\n" | save --append PACKAGES.adoc
                        }
                    }
                } else {
                    "No packages found in pkgs/ directory\n" | save --append PACKAGES.adoc
                }
            } else {
                "No pkgs/ directory found in this branch\n" | save --append PACKAGES.adoc
            }
        } else {
            print $"Failed to checkout branch: origin/($branch)"
            $"\n== ($domain) Domain\n\nError: Could not access branch origin/($branch)\n" | save --append PACKAGES.adoc
        }
    }

    # Add footer
    let now = (date now | format date "%Y-%m-%d %H:%M:%S")
    let footer = $"\n---\n\n_Generated on ($now) by catalog-packages script_\n"
    $footer | save --append PACKAGES.adoc

    # Copy the generated catalog back to the original directory
    print "Copying PACKAGES.adoc back to main worktree..."
    cp PACKAGES.adoc $"($original_dir)/PACKAGES.adoc"

    # Return to original directory and clean up worktree
    cd $original_dir

    print "Cleaning up temporary worktree..."
    try {
        ^git worktree remove $worktree_path --force
        print $"✅ Temporary worktree removed: ($worktree_path)"
    } catch {
        print $"⚠️  Warning: Could not remove temporary worktree at ($worktree_path)"
        print "You may need to remove it manually with: git worktree remove $worktree_path --force"
    }

    print "✅ Package catalog generated in PACKAGES.adoc"
}
