#!/usr/bin/env python3
"""
Release script for WinDock - Python version of the GitHub Actions workflow.
This script handles the entire release process:
1. Version bumping (major, minor, patch)
2. Building the app
3. Creating DMG
4. Creating git tag
5. Generating release notes
6. Creating GitHub release (if GitHub CLI is installed)
7. Submitting formula to Homebrew tap (if GitHub CLI is installed)

Usage:
    python release.py [major|minor|patch]

Optional Dependencies:
    For enhanced functionality, you can install these optional packages:
    - GitPython: `pip install gitpython`
    - PyGithub: `pip install PyGithub` (for future GitHub API integration)
    - GitHub CLI (`gh`): Required for automatic Homebrew tap submission
"""

import argparse
import importlib.util
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

# Check for optional dependencies
HAVE_GITPYTHON = importlib.util.find_spec("git") is not None


class ReleaseManager:
    def __init__(self):
        self.root_dir = Path(__file__).resolve().parent
        self.info_plist_path = self.root_dir / "WinDock" / "Info.plist"
        self.build_dir = self.root_dir / "build"
        self.release_dir = self.build_dir / "Build" / "Products" / "Release"
        self.app_path = self.release_dir / "WinDock.app"
        self.current_version = None
        self.new_version = None
        self.dry_run = False

    def run(self, version_type="patch"):
        """Main execution flow for the release process."""
        print(f"🚀 Starting WinDock release process ({version_type})...")

        # Clean up any stale resources first
        self.cleanup_stale_resources()

        self.get_current_version()
        self.calculate_new_version(version_type)
        self.update_version_in_plist()
        self.build_app()
        # self.create_dmg()

        # Git operations
        self.commit_version_bump()
        self.create_tag()
        self.generate_release_notes()
        self.create_github_release()
        self.submit_to_homebrew()

        self.cleanup()
        print(f"✅ Release process completed successfully! Version {self.new_version} released.")
        print("🍺 If Homebrew tap submission was successful, the formula will be available in your tap.")

    def cleanup_stale_resources(self):
        """Clean up any stale resources that might interfere with the release process."""
        print("🧹 Cleaning up stale resources...")

        # Remove existing DMG and ZIP files
        dmg_path = self.root_dir / "WinDock.dmg"
        zip_path = self.root_dir / "WinDock.zip"

        for file_path in [dmg_path, zip_path]:
            if file_path.exists():
                try:
                    file_path.unlink()
                    print(f"🗑️ Removed existing {file_path.name}")
                except Exception as e:
                    print(f"⚠️ Warning: Could not remove {file_path.name}: {e}")

        # Unmount any existing WinDock volumes
        try:
            # Try to unmount any mounted WinDock volumes
            result = subprocess.run(["mount"], capture_output=True, text=True)
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "WinDock" in line and "/Volumes/" in line:
                        # Extract volume path
                        parts = line.split(" on ")
                        if len(parts) > 1:
                            volume_path = parts[1].split(" (")[0]
                            try:
                                subprocess.run(["hdiutil", "detach", volume_path], capture_output=True, check=False)
                                print(f"🗑️ Unmounted {volume_path}")
                            except Exception:
                                pass
        except Exception:
            pass  # Ignore any errors during cleanup

    def get_current_version(self):
        """Get the current version from Info.plist."""
        try:
            # Read Info.plist using Python's plistlib instead of plutil
            with open(self.info_plist_path, "rb") as f:
                plist_data = plistlib.load(f)

            if "CFBundleShortVersionString" in plist_data:
                self.current_version = plist_data["CFBundleShortVersionString"]
                print(f"📊 Current version: {self.current_version}")
            else:
                self.current_version = "1.0.0"
                print(f"📊 No existing version found, defaulting to: {self.current_version}")
        except Exception as e:
            raise RuntimeError(f"❌ Error reading Info.plist: {e}")

    def calculate_new_version(self, version_type):
        """Calculate the new version based on the bump type."""
        try:
            # Split version into components
            parts = self.current_version.split(".")
            major = int(parts[0])
            minor = int(parts[1]) if len(parts) > 1 else 0
            patch = int(parts[2]) if len(parts) > 2 else 0

            # Bump version according to semantic versioning
            if version_type == "major":
                major += 1
                minor = 0
                patch = 0
            elif version_type == "minor":
                minor += 1
                patch = 0
            elif version_type == "patch":
                patch += 1

            self.new_version = f"{major}.{minor}.{patch}"
            self.tag_name = f"v{self.new_version}"
            print(f"📈 New version: {self.new_version}")
        except Exception as e:
            raise RuntimeError(f"❌ Error calculating new version: {e}")

    def update_version_in_plist(self):
        """Update the version in Info.plist."""
        if self.dry_run:
            print(f"🔍 [DRY RUN] Would update Info.plist with version {self.new_version}")
            return

        try:
            # Read the current plist data
            with open(self.info_plist_path, "rb") as f:
                plist_data = plistlib.load(f)

            # Update versions
            plist_data["CFBundleShortVersionString"] = self.new_version
            plist_data["CFBundleVersion"] = self.new_version

            # Write the updated plist back to file
            with open(self.info_plist_path, "wb") as f:
                plistlib.dump(plist_data, f)

            print(f"📝 Updated Info.plist with version {self.new_version}")

            # Also update the Homebrew tap formula version
            self.update_homebrew_formula_version()
        except Exception as e:
            raise RuntimeError(f"❌ Error updating Info.plist: {e}")

    def update_homebrew_formula_version(self):
        """Update the version in the Homebrew formula file."""
        formula_path = self.root_dir / "homebrew-tap" / "Formula" / "windock.rb"

        if not formula_path.exists():
            print("⚠️ Warning: Homebrew formula file not found, skipping version update")
            return

        try:
            # Read the formula file
            with open(formula_path, "r") as f:
                content = f.read()

            # Update version
            updated_content = re.sub(r'version "[\d\.]+"', f'version "{self.new_version}"', content)

            # Update the URL to use the new version
            updated_content = re.sub(
                r'url "https://github\.com/barnuri/win-dock/releases/download/v[\d\.]+/WinDock\.zip"',
                f'url "https://github.com/barnuri/win-dock/releases/download/v{self.new_version}/WinDock.zip"',
                updated_content,
            )

            # Write back to file
            with open(formula_path, "w") as f:
                f.write(updated_content)

            print(f"📝 Updated Homebrew formula with version {self.new_version}")
        except Exception as e:
            print(f"⚠️ Warning: Error updating Homebrew formula: {e}")
            print("You may need to update the formula version manually.")

    def build_app(self):
        """Build the application using the build.sh script."""
        print("🔨 Building WinDock...")

        # We still need to run the build script as it contains Xcode build commands
        try:
            build_script = self.root_dir / "build.sh"
            # Ensure script is executable
            os.chmod(build_script, 0o755)

            # Run the build script
            subprocess.run([str(build_script)], check=True)

            # Verify the build was successful
            if not self.app_path.exists():
                raise RuntimeError(f"❌ Build failed - WinDock.app not found at {self.app_path}")

            print("✅ Build successful")

            # List files in the Release directory using Python instead of ls
            print(f"Contents of {self.release_dir}:")
            for item in self.release_dir.iterdir():
                item_stats = item.stat()
                size = item_stats.st_size
                mod_time = datetime.fromtimestamp(item_stats.st_mtime).strftime("%b %d %H:%M")
                is_dir = "d" if item.is_dir() else "-"
                print(f"{is_dir} {size:10} {mod_time} {item.name}")

        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"❌ Build failed: {e}")
        except Exception as e:
            raise RuntimeError(f"❌ Error during build process: {e}")

    def create_dmg(self):
        """Create a DMG file for distribution."""
        print("📦 Creating DMG archive...")
        dmg_name = "WinDock.dmg"
        dmg_path = self.root_dir / dmg_name

        if self.dry_run:
            print(f"🔍 [DRY RUN] Would create DMG: {dmg_name}")
            return

        try:
            # Clean up any existing DMG file first
            if dmg_path.exists():
                print(f"🗑️ Removing existing DMG: {dmg_name}")
                dmg_path.unlink()

            # Unmount any existing WinDock volumes that might be mounted
            try:
                volume_name = f"WinDock {self.new_version}"
                subprocess.run(
                    ["hdiutil", "detach", f"/Volumes/{volume_name}"],
                    capture_output=True,
                    check=False,  # Don't fail if nothing to detach
                )
                # Also try to detach any generic WinDock volumes
                subprocess.run(
                    ["hdiutil", "detach", "/Volumes/WinDock"],
                    capture_output=True,
                    check=False,  # Don't fail if nothing to detach
                )
            except Exception:
                pass  # Ignore detach errors

            # Create temporary directory for DMG creation
            with tempfile.TemporaryDirectory() as temp_dir:
                dmg_temp = Path(temp_dir)

                # Copy the app to the temporary directory
                app_copy_dest = dmg_temp / "WinDock.app"
                shutil.copytree(self.app_path, app_copy_dest)

                # Create symbolic link to Applications
                applications_link = dmg_temp / "Applications"
                os.symlink("/Applications", applications_link)

                # We still need hdiutil for creating DMG as it's macOS specific
                # and there's no direct Python equivalent
                volume_name = f"WinDock {self.new_version}"
                subprocess.run(
                    [
                        "hdiutil",
                        "create",
                        "-volname",
                        volume_name,
                        "-srcfolder",
                        str(dmg_temp),
                        "-ov",
                        "-format",
                        "UDZO",
                        "-imagekey",
                        "zlib-level=9",
                        str(dmg_path),
                    ],
                    check=True,
                )

            print(f"✅ Created DMG: {dmg_name}")

            # Show file info using Python instead of ls
            if dmg_path.exists():
                size_bytes = dmg_path.stat().st_size
                size_mb = size_bytes / (1024 * 1024)
                mod_time = datetime.fromtimestamp(dmg_path.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
                print(f"File: {dmg_path.name}")
                print(f"Size: {size_mb:.2f} MB ({size_bytes:,} bytes)")
                print(f"Modified: {mod_time}")

        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"❌ Error creating DMG: {e}")
        except Exception as e:
            raise RuntimeError(f"❌ Error during DMG creation: {e}")

    def commit_version_bump(self):
        """Commit the version bump to git."""
        print("📝 Committing version bump...")

        if self.dry_run:
            print(f"🔍 [DRY RUN] Would commit and push version bump to {self.new_version}")
            return

        # Files to commit
        files_to_commit = [str(self.info_plist_path)]

        # Add Homebrew formula file if it exists
        formula_path = self.root_dir / "homebrew-tap" / "Formula" / "windock.rb"
        if formula_path.exists():
            files_to_commit.append(str(formula_path))

        # Check if we have GitPython available for a more Pythonic approach
        if HAVE_GITPYTHON:
            try:
                import git

                repo = git.Repo(self.root_dir)

                # Stage the files
                for file_path in files_to_commit:
                    repo.git.add(file_path)

                # Commit changes
                repo.index.commit(f"Bump version to {self.new_version}")

                # Push changes
                origin = repo.remote("origin")
                push_info = origin.push()

                if not push_info[0].flags & git.PushInfo.ERROR:
                    print("✅ Changes committed and pushed successfully")
                else:
                    print("⚠️ Warning: Could not push version bump commit")
                    print("You may need to push manually with 'git push'")
            except Exception as e:
                print(f"⚠️ Warning: Git operations with GitPython failed: {e}")
                print("Falling back to subprocess for git operations")
                self._git_commit_via_subprocess(files_to_commit)
        else:
            # Use subprocess approach if GitPython is not available
            self._git_commit_via_subprocess(files_to_commit)

    def _git_commit_via_subprocess(self, files_to_commit=None):
        """Helper method to commit using subprocess."""
        if files_to_commit is None:
            files_to_commit = [str(self.info_plist_path)]

        try:
            # Add and commit changes
            for file_path in files_to_commit:
                subprocess.run(["git", "add", file_path], check=True)
            subprocess.run(["git", "commit", "-m", f"Bump version to {self.new_version}"], check=True)

            # Push changes
            push_result = subprocess.run(["git", "push"], capture_output=True, text=True)
            if push_result.returncode != 0:
                print(f"⚠️ Warning: Could not push version bump commit: {push_result.stderr}")
                print("You may need to push manually with 'git push'")
            else:
                print("✅ Changes committed and pushed successfully")
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Warning: Git operations failed: {e}")
            print("Continuing with release process, but you may need to commit and push manually.")

    def create_tag(self):
        """Create and push a Git tag for the release."""
        print(f"🏷️ Creating release tag: {self.tag_name}")

        if self.dry_run:
            print(f"🔍 [DRY RUN] Would create and push tag {self.tag_name}")
            return

        # Check if we have GitPython available for a more Pythonic approach
        if HAVE_GITPYTHON:
            try:
                import git

                repo = git.Repo(self.root_dir)

                # Create tag
                repo.create_tag(self.tag_name, message=f"Version {self.new_version}")

                # Push tag
                origin = repo.remote("origin")
                push_info = origin.push(self.tag_name)

                if not push_info[0].flags & git.PushInfo.ERROR:
                    print(f"✅ Tag {self.tag_name} created and pushed successfully")
                else:
                    print(f"⚠️ Warning: Could not push tag {self.tag_name}")
                    print(f"You may need to push the tag manually with 'git push origin {self.tag_name}'")
            except Exception as e:
                print(f"⚠️ Warning: Git tag operations with GitPython failed: {e}")
                print("Falling back to subprocess for git tag operations")
                self._git_tag_via_subprocess()
        else:
            # Use subprocess approach if GitPython is not available
            self._git_tag_via_subprocess()

    def _git_tag_via_subprocess(self):
        """Helper method to create and push tag using subprocess."""
        try:
            # Create and push tag
            subprocess.run(["git", "tag", self.tag_name], check=True)
            push_result = subprocess.run(["git", "push", "origin", self.tag_name], capture_output=True, text=True)

            if push_result.returncode != 0:
                print(f"⚠️ Warning: Could not push tag: {push_result.stderr}")
                print(f"You may need to push the tag manually with 'git push origin {self.tag_name}'")
            else:
                print(f"✅ Tag {self.tag_name} created and pushed successfully")
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Warning: Creating tag failed: {e}")
            print("Continuing with release process, but you may need to create and push the tag manually.")

    def generate_release_notes(self):
        """Generate release notes based on git commits."""
        print("📝 Generating release notes...")
        try:
            # Check if we have GitPython available
            if HAVE_GITPYTHON:
                # Import GitPython here to avoid errors if it's not installed
                import git

                # Initialize repository
                repo = git.Repo(self.root_dir)

                # Try to get the previous tag
                last_tag = None
                for tag in repo.tags:
                    last_tag = tag.name
                    break  # Get the most recent tag

                # Get commits since last tag or all commits if no tag
                if last_tag:
                    commits_text = []
                    for commit in repo.iter_commits(f"{last_tag}..HEAD^"):
                        commits_text.append(f"- {commit.summary}")
                    commits = "\n".join(commits_text)
                else:
                    commits_text = []
                    for commit in repo.iter_commits():
                        commits_text.append(f"- {commit.summary}")
                    commits = "\n".join(commits_text)
            else:
                # Fallback to subprocess if GitPython is not available
                get_last_tag = subprocess.run(
                    ["git", "describe", "--tags", "--abbrev=0", "HEAD^"], capture_output=True, text=True
                )

                # Get commits since last tag or all commits if no tag
                if get_last_tag.returncode == 0:
                    last_tag = get_last_tag.stdout.strip()
                    commits_cmd = ["git", "log", "--oneline", "--pretty=format:- %s", f"{last_tag}..HEAD^"]
                else:
                    commits_cmd = ["git", "log", "--oneline", "--pretty=format:- %s", "HEAD"]

                commits = subprocess.run(commits_cmd, capture_output=True, text=True, check=True).stdout

            # Create release notes content
            self.release_notes = f"""## What's Changed

{commits}

## Installation

1. Download `WinDock.dmg`
2. Open the DMG file
3. Drag `WinDock.app` to the Applications folder
4. Run the app from Applications
"""

            # Save to file
            release_notes_path = self.root_dir / "release_notes.md"
            with open(release_notes_path, "w") as f:
                f.write(self.release_notes)

            print("✅ Generated release notes")
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Warning: Error generating release notes: {e}")
            self.release_notes = f"## WinDock {self.new_version}\n\nReleased on {datetime.now().strftime('%Y-%m-%d')}"
            print("Using basic release notes instead.")

    def create_github_release(self):
        """Create a GitHub release using the GitHub CLI if available."""
        print("🌐 Creating GitHub release...")

        if self.dry_run:
            print(f"🔍 [DRY RUN] Would create GitHub release for tag {self.tag_name}")
            return

        # Try to check if PyGithub is available as an alternative to gh CLI
        try:
            import importlib.util

            pygithub_spec = importlib.util.find_spec("github")
            has_pygithub = pygithub_spec is not None
        except Exception:
            has_pygithub = False

        # Check if GitHub CLI is installed (preferred method)
        has_gh_cli = False
        try:
            subprocess.run(["gh", "--version"], capture_output=True, check=True)
            has_gh_cli = True
        except (subprocess.CalledProcessError, FileNotFoundError):
            has_gh_cli = False

        if not (has_gh_cli or has_pygithub):
            print("⚠️ Neither GitHub CLI (gh) nor PyGithub found. Skipping GitHub release creation.")
            print("To create the release manually, go to the repository's releases page")
            print(f"and create a new release with tag '{self.tag_name}'.")
            return

        # Create a ZIP archive of the app bundle
        app_zip_file = self.root_dir / "WinDock.zip"
        if self.app_path.exists():
            print("📦 Creating ZIP archive of WinDock.app...")
            try:
                # Use shutil.make_archive to create a proper zip archive
                shutil.make_archive(
                    str(app_zip_file)[:-4],  # Path without .zip extension
                    "zip",  # Archive format
                    self.release_dir,  # Root directory to archive
                    "WinDock.app",  # Base directory to include
                )
                print(f"✅ Created ZIP archive: {app_zip_file}")
            except Exception as e:
                print(f"⚠️ Warning: Failed to create ZIP archive: {e}")
        else:
            print(f"⚠️ Warning: App bundle not found at {self.app_path}")

        # Check if the DMG file exists
        dmg_file = self.root_dir / "WinDock.dmg"
        if not dmg_file.exists():
            print(f"⚠️ Warning: DMG file not found at {dmg_file}")

        # Prepare release parameters
        release_name = f"WinDock {self.new_version}"
        body_path = self.root_dir / "release_notes.md"

        # We'll use GitHub CLI for now since PyGithub would require authentication setup
        # which is beyond the scope of this conversion
        if has_gh_cli:
            try:
                # Check if release already exists
                check_release = subprocess.run(["gh", "release", "view", self.tag_name], capture_output=True)

                if check_release.returncode == 0:
                    # Update existing release
                    print(f"🔄 Release {self.tag_name} already exists, updating...")
                    subprocess.run(
                        [
                            "gh",
                            "release",
                            "edit",
                            self.tag_name,
                            "--title",
                            release_name,
                            "--notes-file",
                            str(body_path),
                        ],
                        check=True,
                    )
                else:
                    # Create new release
                    print(f"🆕 Creating new release {self.tag_name}...")
                    create_cmd = [
                        "gh",
                        "release",
                        "create",
                        self.tag_name,
                        "--title",
                        release_name,
                        "--notes-file",
                        str(body_path),
                    ]

                    # Add assets if they exist
                    if dmg_file.exists():
                        create_cmd.append(str(dmg_file))
                    if app_zip_file.exists():
                        create_cmd.append(str(app_zip_file))

                    subprocess.run(create_cmd, check=True)

                # Upload assets if not already present
                if dmg_file.exists():
                    print(f"📤 Uploading {dmg_file.name} to release {self.tag_name}...")
                    subprocess.run([
                        "gh",
                        "release",
                        "upload",
                        self.tag_name,
                        str(dmg_file),
                        "--clobber",  # Overwrite if already exists
                    ])

                # Upload ZIP file if not already included
                if app_zip_file.exists():
                    print(f"📤 Uploading {app_zip_file.name} to release {self.tag_name}...")
                    subprocess.run([
                        "gh",
                        "release",
                        "upload",
                        self.tag_name,
                        str(app_zip_file),
                        "--clobber",  # Overwrite if already exists
                    ])

                print("✅ GitHub release created/updated successfully")
            except subprocess.CalledProcessError as e:
                print(f"⚠️ Warning: GitHub release creation failed: {e}")
                print("You may need to create the release manually through the GitHub web interface.")
        # Note: we could implement PyGithub approach here as an alternative

    def submit_to_homebrew(self):
        """Submit the formula to our Homebrew tap by creating a pull request."""
        print("🍺 Submitting formula to Homebrew tap...")

        if self.dry_run:
            print("🔍 [DRY RUN] Would submit formula to Homebrew tap")
            return

        # Check if we're already in a homebrew tap repo or need to clone it
        homebrew_tap_dir = self.root_dir.parent / "homebrew-windock-temp"
        formula_filename = "windock.rb"

        try:
            # Check if we already have the homebrew tap repository
            if homebrew_tap_dir.exists() and (homebrew_tap_dir / ".git").exists():
                print("🔄 Resetting existing homebrew tap repository...")
                # Change to the cloned directory to run git commands
                original_dir = os.getcwd()
                os.chdir(homebrew_tap_dir)

                # Reset to clean state and pull latest changes
                subprocess.run(["git", "reset", "--hard", "HEAD"], check=True)
                subprocess.run(["git", "clean", "-fd"], check=True)
                subprocess.run(["git", "checkout", "master"], check=False)  # Don't fail if already on master
                subprocess.run(["git", "pull", "origin", "master"], check=True)

                # Go back to original directory
                os.chdir(original_dir)
            else:
                # Clean up any existing directory that's not a git repo
                if homebrew_tap_dir.exists():
                    shutil.rmtree(homebrew_tap_dir)

                # Clone or create the homebrew tap repository
                print("📥 Setting up homebrew tap repository...")
                try:
                    # Try to clone the existing tap repository
                    subprocess.run(
                        ["git", "clone", "https://github.com/barnuri/homebrew-brew", str(homebrew_tap_dir)],
                        check=True,
                    )
                except subprocess.CalledProcessError:
                    # If the repository doesn't exist, we'll create it locally
                    print("📝 Creating new homebrew tap repository...")
                    homebrew_tap_dir.mkdir(parents=True, exist_ok=True)

                    # Change to the new directory
                    original_dir = os.getcwd()
                    os.chdir(homebrew_tap_dir)

                    # Initialize git repository
                    subprocess.run(["git", "init"], check=True)
                    subprocess.run(["git", "branch", "-M", "master"], check=True)

                    # Create initial structure
                    formula_dir = homebrew_tap_dir / "Formula"
                    formula_dir.mkdir(exist_ok=True)

                    # Create initial README
                    readme_content = """# Homebrew Tap for WinDock

This is the official Homebrew tap for WinDock.

## Installation

```bash
brew tap barnuri/brew
brew install windock --no-quarantine
```
"""
                    with open(homebrew_tap_dir / "README.md", "w") as f:
                        f.write(readme_content)

                    # Initial commit
                    subprocess.run(["git", "add", "README.md"], check=True)
                    subprocess.run(["git", "commit", "-m", "Initial commit"], check=True)

                    # Go back to original directory
                    os.chdir(original_dir)

            # Change to the tap directory
            original_dir = os.getcwd()
            os.chdir(homebrew_tap_dir)

            # Ensure Formula directory exists
            formula_dir = homebrew_tap_dir / "Formula"
            formula_dir.mkdir(exist_ok=True)
            formula_path = formula_dir / formula_filename

            # Copy our formula file to the tap
            local_formula_path = self.root_dir / "homebrew-tap" / "Formula" / formula_filename
            if not local_formula_path.exists():
                print(f"⚠️ Warning: Local formula file not found at {local_formula_path}")
                return

            # Copy the formula file
            shutil.copy2(local_formula_path, formula_path)
            print(f"📝 Copied formula to {formula_path}")

            # Update the SHA256 checksum in the formula file
            self.update_formula_checksum(formula_path)

            # Add and commit the formula
            subprocess.run(["git", "add", str(formula_path)], check=True)

            # Check if this is a new formula or an update
            status_result = subprocess.run(
                ["git", "status", "--porcelain", str(formula_path)], capture_output=True, text=True
            )

            is_new_formula = status_result.stdout.strip().startswith("A")
            commit_message = (
                f"windock {self.new_version} (new formula)" if is_new_formula else f"windock {self.new_version}"
            )
            subprocess.run(["git", "commit", "-m", commit_message], check=True)

            # Check if we have GitHub CLI
            subprocess.run(["gh", "--version"], capture_output=True, check=True)

            # Push the branch
            subprocess.run(["git", "push", "-u", "origin", "master"], check=True)

        except Exception as e:
            print(f"⚠️ Warning: Homebrew tap submission failed: {e}")
            print("You may need to update the formula manually in the tap repository.")
        finally:
            # Return to original directory but keep the homebrew tap repo for future use
            os.chdir(original_dir)

    def update_formula_checksum(self, formula_path):
        """Update the SHA256 checksum in the formula file."""
        try:
            # Download the ZIP file to calculate its checksum
            zip_url = f"https://github.com/barnuri/win-dock/releases/download/v{self.new_version}/WinDock.zip"

            print(f"📥 Downloading {zip_url} to calculate checksum...")
            download_result = subprocess.run(
                ["curl", "-L", "-o", "/tmp/WinDock.zip", zip_url], capture_output=True, text=True
            )

            if download_result.returncode != 0:
                print("⚠️ Could not download ZIP file for checksum calculation")
                return

            # Calculate SHA256
            checksum_result = subprocess.run(
                ["shasum", "-a", "256", "/tmp/WinDock.zip"], capture_output=True, text=True, check=True
            )

            sha256 = checksum_result.stdout.split()[0]
            print(f"🔍 Calculated SHA256: {sha256}")

            # Update the formula file
            with open(formula_path, "r") as f:
                content = f.read()

            # Replace the sha256 line
            updated_content = re.sub(r"sha256 :no_check", f'sha256 "{sha256}"', content)

            with open(formula_path, "w") as f:
                f.write(updated_content)

            print("✅ Updated formula with calculated checksum")

            # Clean up temporary file
            try:
                os.unlink("/tmp/WinDock.zip")
            except Exception:
                pass

        except subprocess.CalledProcessError as e:
            print(f"⚠️ Error calculating checksum: {e}")
            print("Using :no_check for SHA256")
        except Exception as e:
            print(f"⚠️ Error updating checksum: {e}")

    def update_cask_checksum(self, cask_path):
        """Update the SHA256 checksum in the cask file."""
        try:
            # Download the ZIP file to calculate its checksum
            zip_url = f"https://github.com/barnuri/win-dock/releases/download/v{self.new_version}/WinDock.zip"

            print(f"📥 Downloading {zip_url} to calculate checksum...")
            download_result = subprocess.run(
                ["curl", "-L", "-o", "/tmp/WinDock.zip", zip_url], capture_output=True, text=True
            )

            if download_result.returncode != 0:
                print("⚠️ Could not download ZIP file for checksum calculation")
                return

            # Calculate SHA256
            checksum_result = subprocess.run(
                ["shasum", "-a", "256", "/tmp/WinDock.zip"], capture_output=True, text=True, check=True
            )

            sha256 = checksum_result.stdout.split()[0]
            print(f"🔍 Calculated SHA256: {sha256}")

            # Update the cask file
            with open(cask_path, "r") as f:
                content = f.read()

            # Replace the sha256 line
            updated_content = re.sub(r"sha256 :no_check", f'sha256 "{sha256}"', content)

            with open(cask_path, "w") as f:
                f.write(updated_content)

            print("✅ Updated cask with calculated checksum")

            # Clean up temporary file
            try:
                os.unlink("/tmp/WinDock.zip")
            except Exception:
                pass

        except subprocess.CalledProcessError as e:
            print(f"⚠️ Error calculating checksum: {e}")
            print("Using :no_check for SHA256")
        except Exception as e:
            print(f"⚠️ Error updating checksum: {e}")

    def cleanup(self):
        """Clean up temporary files created during the release process."""
        print("🧹 Cleaning up...")
        # Only clean up the release notes file
        # We keep the DMG and ZIP files for reference
        files_to_remove = [self.root_dir / "release_notes.md"]

        for file_path in files_to_remove:
            if file_path.exists():
                if file_path.is_dir():
                    shutil.rmtree(file_path)
                else:
                    file_path.unlink()

        print("✅ Cleanup completed")


def main():
    """Main entry point for the script."""
    parser = argparse.ArgumentParser(description="WinDock release script")
    parser.add_argument(
        "version_type",
        nargs="?",
        default="patch",
        choices=["major", "minor", "patch"],
        help="Version bump type (default: patch)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Perform a dry run without making any changes")
    args = parser.parse_args()

    if args.dry_run:
        print("🔍 DRY RUN MODE: No changes will be committed or pushed")

    release_manager = ReleaseManager()
    # Set dry run mode attribute if we implement it
    release_manager.dry_run = args.dry_run if hasattr(args, "dry_run") else False
    try:
        release_manager.run(args.version_type)
        print("🚀 Release script completed successfully!")
        print(f"https://github.com/barnuri/win-dock/releases/tag/{release_manager.tag_name}")
    except Exception as e:
        # revert Info.plist to the original version in case of failure
        print(f"❌ Error during release process: {e}")
        print("Reverting Info.plist to the original version...")
        # use git to reset the file
        subprocess.run(["git", "restore", str(release_manager.info_plist_path)], check=True)


if __name__ == "__main__":
    main()
