#!/usr/bin/env nu

# Catalog all packages across pkgs/* branches and generate PACKAGES.adoc
# This script scans all branches matching pkgs/* pattern and extracts package information

def main [] {
    print "Starting package catalog generation..."

    # Get current branch to restore later
    let current_branch = try {
        ^git branch --show-current | str trim
    } catch {
        "management"  # fallback if no commits yet
    }
    print $"Current branch: ($current_branch)"

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

    # Return to original branch or create it if it doesn't exist
    try {
        ^git checkout --force $current_branch
        print $"Returned to original branch: ($current_branch)"
    } catch {
        try {
            ^git checkout -b $current_branch
            print $"Created and switched to new branch: ($current_branch)"
        } catch {
            print $"Warning: Could not return to or create branch ($current_branch)"
        }
    }

    print "Package catalog generated in PACKAGES.adoc"
}
