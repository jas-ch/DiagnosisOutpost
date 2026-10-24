"""Cloud inference for the on-device classifiers used by the Flutter web app.

Media is received as bytes, processed in memory, and never persisted.
"""

import io
import json
import math
from pathlib import Path
from typing import Any

import librosa
import numpy as np
from PIL import Image

try:
    import tflite_runtime.interpreter as tflite
except ImportError:
    import tensorflow.lite as tflite


_MODELS_DIR = Path(__file__).parent / "models"

_TASKS = ["rash", "wound", "face", "tongue", "cough"]

interpreters: dict[str, tflite.Interpreter] = {}
_label_maps: dict[str, list[str]] = {}
_tongue_meta: dict[str, Any] | None = None


def _load_meta() -> None:
    global _tongue_meta
    if _tongue_meta is not None:
        return
    with open(_MODELS_DIR / "tongue_attributes.json") as f:
        attrs = json.load(f)
    with open(_MODELS_DIR / "tongue_evidence_rules.json") as f:
        rules = json.load(f)
    _tongue_meta = {"attributes": attrs, "rules": rules}


def _load_labels(task: str) -> list[str]:
    if task not in _label_maps:
        path = _MODELS_DIR / f"{task}_labels.json"
        with open(path) as f:
            _label_maps[task] = json.load(f)["classes"]
    return _label_maps[task]


def _load_interpreter(task: str) -> tflite.Interpreter:
    if task not in interpreters:
        model_path = _MODELS_DIR / f"{task}_classifier.tflite"
        interpreters[task] = tflite.Interpreter(model_path=str(model_path))
        interpreters[task].allocate_tensors()
    return interpreters[task]


def _softmax(values: np.ndarray) -> np.ndarray:
    max_val = np.max(values)
    exp_values = np.exp(values - max_val)
    return exp_values / np.sum(exp_values)


def _preprocess_image(image_bytes: bytes, size: int = 224) -> np.ndarray:
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    min_side = min(img.size)
    img = img.crop((
        (img.width - min_side) // 2,
        (img.height - min_side) // 2,
        (img.width + min_side) // 2,
        (img.height + min_side) // 2,
    ))
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    arr = np.array(img, dtype=np.float32)
    arr = (arr / 127.5) - 1.0
    return np.expand_dims(arr, axis=0)


def _quantize_for_tflite(arr: np.ndarray, scale: float, zero_point: int) -> np.ndarray:
    return np.clip(np.round(arr / scale + zero_point), 0, 255).astype(np.uint8)


def _dequantize_from_tflite(arr: np.ndarray, scale: float, zero_point: int) -> np.ndarray:
    return (arr.astype(np.float32) - zero_point) * scale


def classify_image(task: str, image_bytes: bytes) -> dict[str, float]:
    """Run an image classifier and return class probabilities."""
    if task not in ["rash", "wound", "face", "tongue"]:
        raise ValueError(f"Unsupported image task: {task}")

    interpreter = _load_interpreter(task)
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]
    input_shape = input_details["shape"]
    size = int(input_shape[1])

    img_arr = _preprocess_image(image_bytes, size=size)

    if input_details["dtype"] == np.uint8:
        scale, zero_point = input_details["quantization"]
        img_arr = _quantize_for_tflite(img_arr, float(scale), int(zero_point))

    interpreter.set_tensor(input_details["index"], img_arr)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details["index"])

    if output_details["dtype"] == np.uint8:
        scale, zero_point = output_details["quantization"]
        output = _dequantize_from_tflite(output, float(scale), int(zero_point))

    # The bundled image classifiers are trained with softmax outputs, so the
    # TFLite model already returns probabilities. Do not re-apply softmax.
    labels = _load_labels(task)
    return {label: float(p) for label, p in zip(labels, output[0])}


def classify_tongue(image_bytes: bytes) -> dict[str, Any]:
    """Run the multi-task tongue attribute classifier."""
    _load_meta()
    interpreter = _load_interpreter("tongue")
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()
    size = int(input_details["shape"][1])

    img_arr = _preprocess_image(image_bytes, size=size)
    if input_details["dtype"] == np.uint8:
        scale, zero_point = input_details["quantization"]
        img_arr = _quantize_for_tflite(img_arr, float(scale), int(zero_point))

    interpreter.set_tensor(input_details["index"], img_arr)
    interpreter.invoke()

    attr_groups = _tongue_meta["attributes"]["attribute_groups"]
    flat_probs: dict[str, float] = {}
    top_attrs: dict[str, str] = {}

    for idx, (group_name, classes) in enumerate(attr_groups.items()):
        out = interpreter.get_tensor(output_details[idx]["index"])
        if output_details[idx]["dtype"] == np.uint8:
            scale, zero_point = output_details[idx]["quantization"]
            out = _dequantize_from_tflite(out, float(scale), int(zero_point))
        probs = _softmax(out[0])
        for cls, p in zip(classes, probs):
            flat_probs[f"{group_name}.{cls}"] = float(p)
        top_attrs[group_name] = classes[int(np.argmax(probs))]

    return {
        "probabilities": flat_probs,
        "topClass": "; ".join(f"{k}: {v}" for k, v in top_attrs.items()),
        "topConfidence": float(max(flat_probs.values())),
    }


def _audio_to_spectrogram(audio_bytes: bytes, sr: int = 16000, target_size: int = 128) -> np.ndarray:
    """Convert audio bytes to a mel-spectrogram matching the training pipeline."""
    y, _ = librosa.load(io.BytesIO(audio_bytes), sr=sr, mono=True, duration=5.0)
    expected_len = int(sr * 5.0)
    if len(y) < expected_len:
        y = np.pad(y, (0, expected_len - len(y)))
    else:
        y = y[:expected_len]

    mel_spec = librosa.feature.melspectrogram(
        y=y, sr=sr, n_fft=512, hop_length=256, n_mels=target_size
    )
    mel_db = librosa.power_to_db(mel_spec, ref=np.max)
    mel_norm = (mel_db - mel_db.min()) / (mel_db.max() - mel_db.min() + 1e-8)
    img_arr = (mel_norm * 255).astype(np.uint8)
    img = Image.fromarray(img_arr).convert("L").resize((target_size, target_size), Image.Resampling.LANCZOS)
    spec = np.array(img, dtype=np.float32) / 255.0
    return np.expand_dims(np.expand_dims(spec, axis=0), axis=-1)


def classify_cough(audio_bytes: bytes) -> dict[str, float]:
    """Run the cough audio classifier and return class probabilities."""
    interpreter = _load_interpreter("cough")
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    spec = _audio_to_spectrogram(audio_bytes)
    interpreter.set_tensor(input_details["index"], spec)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details["index"])
    # The bundled cough classifier is trained with a softmax output.
    labels = _load_labels("cough")
    return {label: float(p) for label, p in zip(labels, output[0])}
