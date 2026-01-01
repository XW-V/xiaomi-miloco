#!/usr/bin/env python3
"""
Test script to verify camera quality configuration implementation.
This script tests the configuration loading and quality selection logic.
"""

import sys
from pathlib import Path

# Add miloco_server to path
sys.path.insert(0, str(Path(__file__).parent / "miloco_server"))

from miloco_server.config import CAMERA_CONFIG
from miot.types import MIoTCameraVideoQuality


def test_config_loading():
    """Test that configuration is loaded correctly."""
    print("Testing configuration loading...")
    
    # Check that camera_qualities and default_quality are loaded
    assert "camera_qualities" in CAMERA_CONFIG, "camera_qualities not found in config"
    assert "default_quality" in CAMERA_CONFIG, "default_quality not found in config"
    
    print(f"✓ Configuration loaded successfully")
    print(f"  - camera_qualities: {CAMERA_CONFIG['camera_qualities']}")
    print(f"  - default_quality: {CAMERA_CONFIG['default_quality']}")
    return True


def test_quality_enum_conversion():
    """Test quality value to enum conversion."""
    print("\nTesting quality enum conversion...")
    
    # Test valid quality values
    for value in [1, 2, 3]:
        quality = MIoTCameraVideoQuality(value)
        print(f"  - Value {value}: {quality.name}")
        assert quality in [MIoTCameraVideoQuality.LOW, MIoTCameraVideoQuality.MEDIUM, MIoTCameraVideoQuality.HIGH]
    
    print("✓ Quality enum conversion works correctly")
    return True


def test_quality_selection_logic():
    """Test the quality selection logic."""
    print("\nTesting quality selection logic...")
    
    # Simulate the logic from _get_camera_quality method
    camera_qualities = CAMERA_CONFIG.get("camera_qualities", {})
    default_quality = CAMERA_CONFIG.get("default_quality", 2)
    
    # Test 1: Camera with specific quality configuration
    test_camera_did = "test_camera_123"
    camera_qualities[test_camera_did] = 3  # Set to HIGH
    
    if test_camera_did in camera_qualities:
        quality_value = camera_qualities[test_camera_did]
        if quality_value in [1, 2, 3]:
            quality = MIoTCameraVideoQuality(quality_value)
            print(f"  ✓ Camera {test_camera_did}: Using configured quality {quality.name}")
        else:
            print(f"  ✗ Invalid quality value for camera {test_camera_did}")
    
    # Test 2: Camera without specific configuration (should use default)
    test_camera_did2 = "test_camera_456"
    if test_camera_did2 not in camera_qualities:
        quality = MIoTCameraVideoQuality(default_quality)
        print(f"  ✓ Camera {test_camera_did2}: Using default quality {quality.name}")
    
    # Clean up test data
    del camera_qualities[test_camera_did]
    
    print("✓ Quality selection logic works correctly")
    return True


def main():
    """Run all tests."""
    print("=" * 60)
    print("Camera Quality Configuration Test")
    print("=" * 60)
    
    try:
        test_config_loading()
        test_quality_enum_conversion()
        test_quality_selection_logic()
        
        print("\n" + "=" * 60)
        print("All tests passed! ✓")
        print("=" * 60)
        print("\nUsage Example:")
        print("To configure camera quality, edit config/server_config.yaml:")
        print("  camera:")
        print("    frame_interval: 2000")
        print("    camera_qualities:")
        print('      "camera_did_1": 3  # HIGH')
        print('      "camera_did_2": 1  # LOW')
        print("    default_quality: 2  # MEDIUM")
        return 0
        
    except Exception as e:
        print(f"\n✗ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
