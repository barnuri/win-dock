#!/usr/bin/env python3
"""
Simple test script to verify the release.py functionality.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from release import ReleaseManager


def test_release_manager():
    """Test basic functionality of ReleaseManager."""
    try:
        release_manager = ReleaseManager()
        print("✅ ReleaseManager initialized successfully")
        print(f"📁 Root directory: {release_manager.root_dir}")
        print(f"📄 Info.plist path: {release_manager.info_plist_path}")

        # Test version reading
        release_manager.get_current_version()
        print(f"📊 Current version: {release_manager.current_version}")

        # Test version calculation
        release_manager.calculate_new_version("patch")
        print(f"📈 New version would be: {release_manager.new_version}")

        print("✅ Basic functionality test passed!")
        return True

    except Exception as e:
        print(f"❌ Test failed: {e}")
        return False


if __name__ == "__main__":
    success = test_release_manager()
    sys.exit(0 if success else 1)
