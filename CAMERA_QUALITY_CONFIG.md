# Camera Video Quality Configuration

## Overview

This feature allows you to configure different video quality levels for individual cameras by specifying their device IDs (DID) in `config/server_config.yaml`.

## Configuration

Edit `config/server_config.yaml` and add camera-specific quality settings under the `camera` section:

```yaml
# Camera configuration
camera:
  frame_interval: 2000  # Unit: Millisecond (ms)
  
  # Per-camera video quality configuration
  # Format: camera_did: quality_level
  # Quality levels: 1=LOW, 2=MEDIUM, 3=HIGH
  camera_qualities:
    "camera_did_1": 3  # HIGH quality
    "camera_did_2": 1  # LOW quality
    "camera_did_3": 2  # MEDIUM quality
  
  default_quality: 2  # Default to MEDIUM if not specified
```

## Quality Levels

| Value | Enum    | Description |
|-------|----------|-------------|
| 1     | LOW      | Lowest bandwidth usage, lower resolution |
| 2     | MEDIUM   | Balanced quality (default) |
| 3     | HIGH     | Highest quality, more bandwidth |

## How It Works

1. When a camera is started, the system checks if its DID is in the `camera_qualities` configuration
2. If configured, it uses the specified quality level
3. If not configured, it falls back to `default_quality` (MEDIUM by default)
4. Invalid quality values are logged and the default quality is used instead

## Finding Your Camera DIDs

To find your camera device IDs (DIDs):

1. Open the Mi Home app
2. Navigate to your camera devices
3. Check device settings or device info to find the Device ID
4. Alternatively, check the device list in the Miloco server logs

## Example Scenarios

### Scenario 1: Different Quality for Multiple Cameras

```yaml
camera:
  camera_qualities:
    "12345678": 3  # Living room camera - HIGH quality
    "87654321": 1  # Outdoor camera - LOW quality
  default_quality: 2  # Other cameras use MEDIUM
```

### Scenario 2: All Cameras Use Default Quality

```yaml
camera:
  camera_qualities: {}  # Empty - all cameras use default
  default_quality: 2  # MEDIUM for all
```

### Scenario 3: High Quality for All Cameras

```yaml
camera:
  camera_qualities: {}  # No specific config
  default_quality: 3  # HIGH for all cameras
```

## Logging

The system logs the quality selection for each camera:

```
INFO: Using configured quality HIGH for camera 12345678
INFO: Using default quality MEDIUM for camera 87654321
WARNING: Invalid quality value 5 for camera 11111111, using default
```

## Technical Details

- Configuration is loaded from `config/server_config.yaml` at server startup
- Quality settings are applied when cameras are initialized/started
- The `MIoTCameraVideoQuality` enum is used to validate quality values
- Quality changes require server restart to take effect for existing cameras

## Benefits

- **Bandwidth Management**: Use lower quality for cameras with limited bandwidth
- **Performance Optimization**: Reduce CPU/processing load for less critical cameras
- **Customization**: Tailor quality based on camera importance or location
- **Flexibility**: Mix different quality levels across your camera setup

## Troubleshooting

### Camera Not Using Configured Quality

1. Verify the DID in your config matches exactly (case-sensitive)
2. Check server logs for quality selection messages
3. Ensure the quality value is valid (1, 2, or 3)
4. Restart the server after configuration changes

### All Cameras Using Default Quality

- Check that `camera_qualities` is not empty in your config
- Verify the camera DIDs are correctly formatted as strings
- Ensure the YAML syntax is correct (no indentation errors)

## Related Files

- `config/server_config.yaml` - Configuration file
- `miloco_server/config/normal_config.py` - Configuration loader
- `miloco_server/proxy/miot_proxy.py` - Camera proxy with quality logic
- `miot/types.py` - MIoTCameraVideoQuality enum definition
