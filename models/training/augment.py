"""Shared image and audio augmentation utilities for on-device classifiers.

All transforms are intentionally conservative so augmented samples remain
clinically plausible. No new dependencies beyond Pillow, numpy, scipy, librosa,
and soundfile.
"""

import hashlib
import io
import random
import subprocess
from pathlib import Path
from typing import Optional, Tuple

import librosa
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps


# ---------------------------------------------------------------------------
# IMAGE AUGMENTATION
# ---------------------------------------------------------------------------


def _fit_to_square(img: Image.Image, size: Tuple[int, int]) -> Image.Image:
    """Center-crop to square then resize."""
    w, h = img.size
    if w != h:
        min_side = min(w, h)
        left = (w - min_side) // 2
        top = (h - min_side) // 2
        img = img.crop((left, top, left + min_side, top + min_side))
    return img.resize(size, Image.Resampling.LANCZOS)


def _add_noise(img: Image.Image, scale: float = 0.02) -> Image.Image:
    """Add small Gaussian noise in RGB space."""
    arr = np.array(img).astype(np.float32) / 255.0
    noise = np.random.normal(0, scale, arr.shape)
    arr = np.clip(arr + noise, 0.0, 1.0)
    return Image.fromarray((arr * 255).astype(np.uint8))


def augment_image(
    img: Image.Image,
    output_size: Tuple[int, int] = (224, 224),
    seed: Optional[int] = None,
    intensity: str = "medium",
) -> Image.Image:
    """Apply a random but clinically plausible augmentation pipeline.

    Args:
        img: Input PIL image (RGB).
        output_size: Target (H, W).
        seed: Optional RNG seed for reproducibility.
        intensity: "light", "medium", or "heavy".

    Returns:
        Augmented PIL image resized to output_size.
    """
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed % (2**32))

    img = img.convert("RGB")

    # First fit to square so downstream transforms see consistent geometry.
    img = _fit_to_square(img, output_size)

    if intensity == "light":
        rot = 5
        crop = 0.05
        bright = 0.1
        contrast = 0.1
        saturation = 0.1
        noise = 0.01
    elif intensity == "heavy":
        rot = 20
        crop = 0.15
        bright = 0.25
        contrast = 0.25
        saturation = 0.25
        noise = 0.04
    else:  # medium
        rot = 12
        crop = 0.10
        bright = 0.18
        contrast = 0.18
        saturation = 0.18
        noise = 0.025

    # Random rotation
    if random.random() < 0.7:
        angle = random.uniform(-rot, rot)
        img = img.rotate(angle, fillcolor=(128, 128, 128), resample=Image.Resampling.BILINEAR)

    # Random horizontal flip
    if random.random() < 0.5:
        img = ImageOps.mirror(img)

    # Random crop / zoom
    if random.random() < 0.6:
        w, h = img.size
        crop_px = int(min(w, h) * random.uniform(0, crop))
        if crop_px > 0:
            img = img.crop((crop_px, crop_px, w - crop_px, h - crop_px))
            img = img.resize((w, h), Image.Resampling.LANCZOS)

    # Color jitter
    if random.random() < 0.5:
        factor = random.uniform(1 - bright, 1 + bright)
        img = ImageEnhance.Brightness(img).enhance(factor)
    if random.random() < 0.5:
        factor = random.uniform(1 - contrast, 1 + contrast)
        img = ImageEnhance.Contrast(img).enhance(factor)
    if random.random() < 0.4:
        factor = random.uniform(1 - saturation, 1 + saturation)
        img = ImageEnhance.Color(img).enhance(factor)

    # Gaussian blur occasionally
    if random.random() < 0.1:
        radius = random.uniform(0.5, 1.5)
        img = img.filter(ImageFilter.GaussianBlur(radius=radius))

    # Noise
    if random.random() < 0.4:
        img = _add_noise(img, scale=noise)

    # Final resize to ensure exact output size
    img = img.resize(output_size, Image.Resampling.LANCZOS)
    return img



# ---------------------------------------------------------------------------
# AUDIO LOADING / AUGMENTATION / SPECTROGRAMS
# ---------------------------------------------------------------------------


def load_audio_ffmpeg(path: Path, sr: int = 16000, duration: Optional[float] = 5.0) -> np.ndarray:
    """Load an audio file with ffmpeg, returning a mono float32 array at `sr`."""
    path = Path(path)
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-i",
        str(path),
        "-ar",
        str(sr),
        "-ac",
        "1",
        "-f",
        "wav",
        "-",
    ]
    if duration:
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-t", str(duration), "-i", str(path), "-ar", str(sr), "-ac", "1", "-f", "wav", "-"]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed for {path}: {proc.stderr.decode()[:200]}")
    y, out_sr = librosa.load(io.BytesIO(proc.stdout), sr=sr, mono=True, duration=duration)
    return y


def load_audio(path: Path, sr: int = 16000, duration: Optional[float] = 5.0) -> np.ndarray:
    """Load audio, falling back to ffmpeg when librosa/soundfile cannot read the codec."""
    try:
        y, _ = librosa.load(str(path), sr=sr, mono=True, duration=duration)
        return y
    except Exception:
        return load_audio_ffmpeg(path, sr=sr, duration=duration)


def _pad_or_trim(y: np.ndarray, length: int) -> np.ndarray:
    if len(y) >= length:
        return y[:length]
    return np.pad(y, (0, length - len(y)), mode="constant")


def augment_audio(
    y: np.ndarray,
    sr: int = 16000,
    seed: Optional[int] = None,
) -> np.ndarray:
    """Apply a random audio augmentation chain.

    Args:
        y: Mono float32 audio array.
        sr: Sample rate.
        seed: Optional RNG seed.

    Returns:
        Augmented audio array of the same length as input.
    """
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed % (2**32))

    length = len(y)

    # Time stretch (preserve pitch)
    if random.random() < 0.5:
        rate = random.uniform(0.85, 1.15)
        y = librosa.effects.time_stretch(y, rate=rate)
        y = _pad_or_trim(y, length)

    # Pitch shift
    if random.random() < 0.5:
        n_steps = random.uniform(-2.0, 2.0)
        y = librosa.effects.pitch_shift(y, sr=sr, n_steps=n_steps)

    # Add noise
    if random.random() < 0.5:
        rms = max(np.sqrt(np.mean(y**2)), 1e-6)
        snr_db = random.uniform(20, 40)
        noise_rms = rms / (10 ** (snr_db / 20))
        noise = np.random.normal(0, noise_rms, y.shape)
        y = y + noise

    # Volume scaling
    if random.random() < 0.5:
        y = y * random.uniform(0.8, 1.2)

    return np.clip(y, -1.0, 1.0)


def audio_to_spectrogram(
    y: np.ndarray,
    sr: int = 16000,
    n_mels: int = 128,
    target_size: Tuple[int, int] = (128, 128),
) -> Image.Image:
    """Convert a mono audio clip to a mel-spectrogram PNG image."""
    # Ensure fixed input length for consistent spectrogram shape.
    expected_len = int(sr * 5.0)
    y = _pad_or_trim(y, expected_len)

    mel_spec = librosa.feature.melspectrogram(
        y=y,
        sr=sr,
        n_fft=512,
        hop_length=256,
        n_mels=n_mels,
    )
    mel_db = librosa.power_to_db(mel_spec, ref=np.max)
    # Normalize to 0-255
    mel_norm = (mel_db - mel_db.min()) / (mel_db.max() - mel_db.min() + 1e-8)
    img_arr = (mel_norm * 255).astype(np.uint8)
    img = Image.fromarray(img_arr)
    img = img.convert("L")
    img = img.resize((target_size[1], target_size[0]), Image.Resampling.LANCZOS)
    return img


def spectrogram_augment(img: Image.Image, seed: Optional[int] = None) -> Image.Image:
    """Light spec-augment style masking for spectrogram images."""
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed % (2**32))

    arr = np.array(img).astype(np.float32)
    h, w = arr.shape

    # Horizontal (time) mask
    if random.random() < 0.5:
        width = max(1, int(w * random.uniform(0.05, 0.15)))
        start = random.randint(0, max(0, w - width))
        arr[:, start : start + width] = arr.mean()

    # Vertical (frequency) mask
    if random.random() < 0.5:
        height = max(1, int(h * random.uniform(0.05, 0.15)))
        start = random.randint(0, max(0, h - height))
        arr[start : start + height, :] = arr.mean()

    return Image.fromarray(arr.astype(np.uint8))
