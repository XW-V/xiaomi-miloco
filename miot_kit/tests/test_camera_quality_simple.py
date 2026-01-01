#!/usr/bin/env python3
"""
Simple test script to verify camera quality configuration in server_config.yaml.
This script tests YAML configuration structure without requiring full module dependencies.
"""

import sys
import yaml
from pathlib import Path


def test_config_yaml():
    """Test that configuration file has correct structure."""
    print("=" * 60)
    print("Testing Camera Quality Configuration")
    print("=" * 60)
    
    config_path = Path(__file__).parent / "config" / "server_config.yaml"
    
    if not config_path.exists():
        print(f"✗ Configuration file not found: {config_path}")
        return False
    
    print(f"\n✓ Found configuration file: {config_path}")
    
    # Load YAML
    with open(config_path, 'r', encoding='utf-8') as f:
        config = yaml.safe_load(f)
    
    # Check camera configuration
    if 'camera' not in config:
        print("✗ 'camera' section not found in config")
        return False
    
    camera_config = config['camera']
    print(f"\n✓ Found camera configuration")
    
    # Check frame_interval
    if 'frame_interval' in camera_config:
        print(f"  - frame_interval: {camera_config['frame_interval']} ms")
    
    # Check camera_qualities
    if 'camera_qualities' not in camera_config:
        print("✗ 'camera_qualities' not found in camera config")
        return False
    
    camera_qualities = camera_config['camera_qualities']
    print(f"  - camera_qualities: {camera_qualities}")
    
    if not isinstance(camera_qualities, dict):
        print("✗ 'camera_qualities' must be a dictionary")
        return False
    
    # Check default_quality
    if 'default_quality' not in camera_config:
        print("✗ 'default_quality' not found in camera config")
        return False
    
    default_quality = camera_config['default_quality']
    print(f"  - default_quality: {default_quality}")
    
    if default_quality not in [1, 2, 3]:
        print(f"✗ Invalid default_quality: {default_quality} (must be 1, 2, or 3)")
        return False
    
    # Validate configured camera qualities
    quality_names = {1: 'LOW', 2: 'MEDIUM', 3: 'HIGH'}
    
    if camera_qualities:
        print(f"\n✓ Found {len(camera_qualities)} configured camera(s)")
        for did, quality in camera_qualities.items():
            if quality not in [1, 2, 3]:
                print(f"  ✗ Camera {did}: Invalid quality {quality}")
                return False
            print(f"  ✓ Camera {did}: Quality {quality_names[quality]}")
    else:
        print(f"\n✓ No cameras explicitly configured (will use default quality)")
    
    # Test example configuration
    print("\n" + "=" * 60)
    print("Configuration Example:")
    print("=" * 60)
    print("""
To configure camera quality, edit config/server_config.yaml:

  camera:
    frame_interval: 2000  # Millisecond
    camera_qualities:
      "your_camera_did_1": 3  # HIGH quality
      "your_camera_did_2": 1  # LOW quality
    default_quality: 2  # MEDIUM (used if not specified)

Quality Levels:
  1 = LOW
  2 = MEDIUM (default)
  3 = HIGH

To get your camera DIDs, check your Mi Home app or device list.
""")
    
    print("=" * 60)
    print("All tests passed! ✓")
    print("=" * 60)
    return True


def main():
    """Run test."""
    try:
        success = test_config_yaml()
        return 0 if success else 1
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
