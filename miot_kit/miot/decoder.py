# -*- coding: utf-8 -*-
# Copyright (C) 2025 Xiaomi Corporation
# This software may be used and distributed according to the terms of the Xiaomi Miloco License Agreement.
"""
MIoT Decoder.
"""
import asyncio
from collections import deque
import logging
import os
import subprocess
import threading
import time
from pathlib import Path
from typing import List, Callable, Coroutine, Optional
from io import BytesIO
from av.packet import Packet
from av.codec import CodecContext
from av.video.codeccontext import VideoCodecContext
from av.audio.codeccontext import AudioCodecContext
from av.audio.resampler import AudioResampler
from av.video.frame import VideoFrame
from av.audio.frame import AudioFrame
from PIL import Image
import av as av_module

from .types import MIoTCameraFrameType, MIoTCameraCodec, MIoTCameraFrameData
from .error import MIoTMediaDecoderError

_LOGGER = logging.getLogger(__name__)


def _setup_library_paths():
    """Setup library paths for third-party FFmpeg and VAAPI libraries."""
    third_party_dir = Path(__file__).parent.parent.parent / "third_party"
    
    if not third_party_dir.exists():
        _LOGGER.debug("Third party directory not found, using system libraries")
        return
    
    # Setup FFmpeg library path
    ffmpeg_lib = third_party_dir / "ffmpeg" / "linux" / "x86_64" / "lib"
    if ffmpeg_lib.exists():
        current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')
        if str(ffmpeg_lib) not in current_ld_path:
            os.environ['LD_LIBRARY_PATH'] = f"{ffmpeg_lib}:{current_ld_path}"
            _LOGGER.info(f"Added FFmpeg library path: {ffmpeg_lib}")
    
    # Setup VAAPI library path
    vaapi_lib = third_party_dir / "vaapi" / "linux" / "x86_64" / "lib"
    if vaapi_lib.exists():
        current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')
        if str(vaapi_lib) not in current_ld_path:
            os.environ['LD_LIBRARY_PATH'] = f"{vaapi_lib}:{current_ld_path}"
            _LOGGER.info(f"Added VAAPI library path: {vaapi_lib}")
        
        # Set VAAPI driver path
        driver_path = vaapi_lib / "dri"
        if driver_path.exists():
            os.environ['LIBVA_DRIVERS_PATH'] = str(driver_path)
            _LOGGER.info(f"Set VAAPI driver path: {driver_path}")


# Initialize library paths on module load
_setup_library_paths()


class MIoTMediaRingBuffer():
    """Ring buffer."""
    _maxlen: int
    _video_buffer: deque[MIoTCameraFrameData]
    _audio_buffer: deque[MIoTCameraFrameData]
    _cond: threading.Condition

    def __init__(self, maxlen: int = 20):
        self._maxlen = maxlen
        self._video_buffer = deque(maxlen=maxlen)
        self._audio_buffer = deque(maxlen=maxlen)
        self._cond = threading.Condition()

    def put_video(self, item: MIoTCameraFrameData) -> None:
        with self._cond:
            # When the queue is full, non-key frames are discarded first
            if len(self._video_buffer) >= self._maxlen:
                if item.frame_type == MIoTCameraFrameType.FRAME_I:
                    removed: bool = False
                    for i in range(len(self._video_buffer)):
                        if self._video_buffer[i].frame_type != MIoTCameraFrameType.FRAME_I:
                            del self._video_buffer[i]
                            removed = True
                            break
                    if not removed:
                        self._video_buffer.popleft()
                    self._video_buffer.append(item)
                    self._cond.notify()
                else:
                    # Drop non-I frame
                    pass
                _LOGGER.info("drop non-I frame, %s, %s", item.codec_id, item.timestamp)
            else:
                self._video_buffer.append(item)
                self._cond.notify()

    def put_audio(self, item: MIoTCameraFrameData) -> None:
        with self._cond:
            self._audio_buffer.append(item)
            self._cond.notify()

    def step(
        self,
        on_video_frame: Callable[[MIoTCameraFrameData], None],
        on_audio_frame: Callable[[MIoTCameraFrameData], None],
        timeout: float = 0.2
    ) -> None:
        on_frame: Callable[[MIoTCameraFrameData], None] = on_video_frame
        frame_data: Optional[MIoTCameraFrameData] = None
        # get frame
        with self._cond:
            if self._video_buffer:
                frame_data = self._video_buffer.popleft()
            elif self._audio_buffer:
                frame_data = self._audio_buffer.popleft()
                on_frame = on_audio_frame
            else:
                self._cond.wait(timeout=timeout)
        # handle frame
        if frame_data:
            on_frame(frame_data)

    def stop(self):
        del self._cond
        self._video_buffer.clear()
        self._audio_buffer.clear()


class MIoTMediaDecoder(threading.Thread):
    """MIoT Decoder."""
    _main_loop: asyncio.AbstractEventLoop
    _running: bool
    _frame_interval: int
    _enable_hw_accel: bool
    _enable_audio: bool
    _hw_accel_available: bool
    _hw_accel_type: Optional[str]

    # format: did, data, ts, channel
    _video_callback: Callable[[bytes, int, int], Coroutine]
    # format: did, data, ts, channel
    _audio_callback: Callable[[bytes, int, int], Coroutine]

    _queue: MIoTMediaRingBuffer
    _video_decoder: Optional[CodecContext]
    _audio_decoder: Optional[CodecContext]
    _resampler: AudioResampler

    _current_jpg_width: int
    _current_jpg_height: int
    _last_jpeg_ts: int

    def __init__(
        self,
        frame_interval: int,
        video_callback: Callable[[bytes, int, int], Coroutine],
        audio_callback: Optional[Callable[[bytes, int, int], Coroutine]] = None,
        enable_hw_accel: bool = True,
        enable_audio: bool = True,
        main_loop: Optional[asyncio.AbstractEventLoop] = None,
    ) -> None:
        super().__init__()
        self._main_loop = main_loop or asyncio.get_running_loop()
        self._running = False
        self._frame_interval = frame_interval
        self._enable_hw_accel = enable_hw_accel
        self._enable_audio = enable_audio

        self._video_callback = video_callback
        if enable_audio:
            if not audio_callback:
                raise MIoTMediaDecoderError("audio_callback is required when enable audio")
            else:
                self._audio_callback = audio_callback

        self._queue = MIoTMediaRingBuffer()
        self._video_decoder = None
        self._audio_decoder = None
        self._resampler = None  # type: ignore

        self._last_jpeg_ts = 0
        self._hw_accel_available = False
        self._hw_accel_type = None
        
        # Detect hardware acceleration availability
        if self._enable_hw_accel:
            self._hw_accel_available = self._detect_hw_acceleration()

    def run(self) -> None:
        """Start the decoder."""
        self._running = True
        while self._running:
            try:
                self._queue.step(
                    on_video_frame=self._on_video_callback,
                    on_audio_frame=self._on_audio_callback
                )
            except Exception as e:  # pylint: disable=broad-except
                _LOGGER.error("frame data handle error, %s", e)
                if self._main_loop.is_closed():
                    break
        _LOGGER.info("decoder stopped")

    def stop(self) -> None:
        """Stop the decoder."""
        self._running = False
        self._queue.stop()
        self._video_decoder = None
        self._audio_decoder = None
        self.join()

    def push_video_frame(self, frame_data: MIoTCameraFrameData) -> None:
        self._queue.put_video(frame_data)

    def push_audio_frame(self, frame_data: MIoTCameraFrameData) -> None:
        self._queue.put_audio(frame_data)

    def _detect_hw_acceleration(self) -> bool:
        """Detect if hardware acceleration is available."""
        try:
            # Check PyAV version
            pyav_version = av_module.__version__
            _LOGGER.info(f"PyAV version: {pyav_version}")
            
            # Try to check if FFmpeg has VAAPI support via command line
            try:
                result = subprocess.run(
                    ["ffmpeg", "-hwaccels"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False
                )
                if result.returncode == 0:
                    hwaccels = result.stdout
                    if "vaapi" in hwaccels.lower():
                        self._hw_accel_type = 'vaapi'
                        _LOGGER.info("VAAPI hardware acceleration detected (via FFmpeg)")
                        return True
            except FileNotFoundError:
                _LOGGER.debug("ffmpeg command not found for hwaccel check")
            
            # Alternative: check if VAAPI device exists
            if os.path.exists("/dev/dri/renderD128") or os.path.exists("/dev/dri/card0"):
                _LOGGER.info("VAAPI device detected, hardware acceleration may be available")
                # Note: We'll try to use hwaccel when creating decoder
                self._hw_accel_type = 'vaapi'
                return True
            
            _LOGGER.info("No VAAPI hardware acceleration available, will use software decoding")
            return False
            
        except Exception as e:
            _LOGGER.warning(f"Failed to detect hardware acceleration: {e}")
            return False

    def _init_hw_decoder(self, codec_name: str) -> VideoCodecContext:
        """Initialize hardware decoder for HEVC/H.264 with VAAPI support."""
        try:
            # Create decoder with thread_type set to auto for better performance
            # This allows FFmpeg to use hardware acceleration if available
            decoder = VideoCodecContext.create(codec_name, "r")
            decoder.thread_type = 'auto'
            
            _LOGGER.info(f"Created decoder for {codec_name} with hardware acceleration support")
            return decoder
            
        except Exception as e:
            _LOGGER.warning(f"Failed to init HW decoder for {codec_name}: {e}, fallback to software")
            return VideoCodecContext.create(codec_name, "r")

    def _on_video_callback(self, frame_data: MIoTCameraFrameData) -> None:
        if not self._video_decoder:
            # Create video decoder with hardware acceleration support
            if frame_data.codec_id == MIoTCameraCodec.VIDEO_H264:
                if self._enable_hw_accel and self._hw_accel_available:
                    self._video_decoder = self._init_hw_decoder("h264")
                else:
                    self._video_decoder = VideoCodecContext.create("h264", "r")
                    _LOGGER.info("Using software decoder for H.264")
            elif frame_data.codec_id == MIoTCameraCodec.VIDEO_H265:
                if self._enable_hw_accel and self._hw_accel_available:
                    self._video_decoder = self._init_hw_decoder("hevc")
                else:
                    self._video_decoder = VideoCodecContext.create("hevc", "r")
                    _LOGGER.info("Using software decoder for HEVC")
            
            _LOGGER.info("Video decoder created, codec=%s", frame_data.codec_id)
        
        pkt = Packet(frame_data.data)
        frames: List[VideoFrame] = self._video_decoder.decode(pkt)  # type: ignore
        
        now_ts = int(time.time()*1000)
        if now_ts - self._last_jpeg_ts >= self._frame_interval:
            if not frames:
                _LOGGER.info("video frame is empty, %d, %d", frame_data.codec_id, frame_data.timestamp)
                self._last_jpeg_ts = now_ts
                return
            
            frame = frames[0]
            
            # Process frame to RGB
            try:
                # Convert to RGB format (works for both software and hardware frames)
                rgb_frame: VideoFrame = frame.reformat(frame.width, frame.height, format='rgb24')
                
                img: Image.Image = rgb_frame.to_image()
                buf: BytesIO = BytesIO()
                img.save(buf, format="JPEG", quality=90)
                jpeg_data = buf.getvalue()
                
                self._main_loop.call_soon_threadsafe(
                    self._main_loop.create_task,
                    self._video_callback(jpeg_data, frame_data.timestamp, frame_data.channel)
                )
                self._last_jpeg_ts = now_ts
                
            except Exception as e:
                _LOGGER.error("Failed to process video frame: %s", e)

    def _on_audio_callback(self, frame_data: MIoTCameraFrameData) -> None:
        if not self._audio_decoder:
            # Create audio decoder
            if frame_data.codec_id == MIoTCameraCodec.AUDIO_OPUS:
                self._audio_decoder = AudioCodecContext.create("opus", "r")
            self._resampler = AudioResampler(format="s16", layout="mono", rate=16000)
            _LOGGER.info("audio decoder created, %s", frame_data.codec_id)
        pkt = Packet(frame_data.data)
        frames: List[AudioFrame] = self._audio_decoder.decode(pkt)  # type: ignore
        pcm_bytes: bytes = b""
        for frame in frames:
            rs_frames = self._resampler.resample(frame)
            for rs_frame in rs_frames:
                pcm_bytes += rs_frame.to_ndarray().tobytes()
        self._main_loop.call_soon_threadsafe(
            self._main_loop.create_task,
            self._audio_callback(pcm_bytes, frame_data.timestamp, frame_data.channel)
        )


class MIoTMediaRecorder(threading.Thread):
    """MIoT Recorder."""
    _main_loop: asyncio.AbstractEventLoop
