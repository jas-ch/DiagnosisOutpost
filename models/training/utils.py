"""Shared training utilities: dataset loading, label mapping, metrics."""

import csv
import json
import random
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import tensorflow as tf
import yaml


def get_project_root() -> Path:
    """Return repository root (two levels above this file)."""
    return Path(__file__).resolve().parents[2]


def load_config(config_path: str) -> dict:
    """Load a YAML training config."""
    with open(config_path, "r") as f:
        return yaml.safe_load(f)


def set_seeds(seed: int = 42) -> None:
    """Fix random seeds for reproducibility."""
    random.seed(seed)
    np.random.seed(seed)
    tf.random.set_seed(seed)


def get_paths(task: str) -> Tuple[Path, Path]:
    """Return (processed_dir, exported_dir) for a task."""
    root = get_project_root()
    processed = root / "models" / "datasets" / "processed" / task
    exported = root / "models" / "exported"
    exported.mkdir(parents=True, exist_ok=True)
    return processed, exported


def save_label_map(exported_dir: Path, task: str, classes: List[str]) -> Path:
    """Save a JSON label map for the exported model."""
    path = exported_dir / f"{task}_labels.json"
    mapping = {
        "classes": classes,
        "class_to_index": {name: idx for idx, name in enumerate(classes)},
    }
    with open(path, "w") as f:
        json.dump(mapping, f, indent=2)
    return path


def load_manifest(manifest_path: Path) -> List[dict]:
    """Load a processed split CSV manifest."""
    with open(manifest_path, "r", newline="") as f:
        return list(csv.DictReader(f))


def compute_class_weights(manifest_path: Path, class_names: List[str]) -> Dict[int, float]:
    """Compute balanced class weights from a manifest."""
    rows = load_manifest(manifest_path)
    class_to_idx = {name: idx for idx, name in enumerate(class_names)}
    counts = Counter()
    for row in rows:
        label = row.get("label")
        if label in class_to_idx:
            counts[class_to_idx[label]] += 1
    if not counts:
        return {}
    total = sum(counts.values())
    n_classes = len(class_names)
    weights = {}
    for idx in range(n_classes):
        count = counts.get(idx, 0)
        if count > 0:
            weights[idx] = total / (n_classes * count)
        else:
            weights[idx] = 0.0
    return weights


def _parse_image(path: str, label: int, image_size: Tuple[int, int], num_classes: int, channels: int):
    img = tf.io.read_file(path)
    img = tf.image.decode_jpeg(img, channels=channels)
    img = tf.image.resize(img, image_size)
    img = tf.cast(img, tf.float32)
    # MobileNetV2 preprocessing: scale to [-1, 1].
    img = (img / 127.5) - 1.0
    return img, tf.one_hot(label, depth=num_classes)


def _parse_spectrogram(
    path: str, label: int, image_size: Tuple[int, int], num_classes: int
):
    img = tf.io.read_file(path)
    img = tf.image.decode_png(img, channels=1)
    img = tf.image.resize(img, image_size)
    img = tf.cast(img, tf.float32) / 255.0
    return img, tf.one_hot(label, depth=num_classes)


def build_dataset(
    manifest_path: Path,
    class_names: List[str],
    image_size: List[int],
    batch_size: int,
    color_mode: str = "rgb",
    seed: int = 42,
    shuffle: bool = True,
) -> tf.data.Dataset:
    """Build a tf.data.Dataset from a processed split CSV manifest."""
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    rows = load_manifest(manifest_path)
    root = get_project_root()
    class_to_idx = {name: idx for idx, name in enumerate(class_names)}

    paths = []
    labels = []
    for row in rows:
        label = row.get("label")
        if label not in class_to_idx:
            continue
        paths.append(str(root / row["path"]))
        labels.append(class_to_idx[label])

    if not paths:
        raise ValueError(f"No valid samples found in {manifest_path}")

    num_classes = len(class_names)
    image_size_tuple = tuple(image_size)

    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if shuffle:
        buffer_size = min(len(paths), 10000)
        ds = ds.shuffle(buffer_size=buffer_size, seed=seed, reshuffle_each_iteration=True)

    if color_mode == "rgb":
        parse_fn = lambda p, l: _parse_image(p, l, image_size_tuple, num_classes, channels=3)
    else:
        parse_fn = lambda p, l: _parse_spectrogram(p, l, image_size_tuple, num_classes)

    ds = ds.map(parse_fn, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.batch(batch_size)
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return ds


def convert_to_tflite(
    model: tf.keras.Model,
    representative_ds: tf.data.Dataset | None = None,
    quantize: bool = False,
) -> bytes:
    """Convert a Keras model to TFLite, optionally applying full INT8 quantization.

    When quantize is True, representative_ds must be provided. The converter uses
    up to 100 batches from the dataset for calibration and produces a model with
    uint8 inputs and outputs.
    """
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantize:
        if representative_ds is None:
            raise ValueError("representative_ds is required for quantization")

        def representative_dataset():
            for x, _ in representative_ds.take(100):
                yield [x]

        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = representative_dataset
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.uint8
        converter.inference_output_type = tf.uint8
    return converter.convert()


class PerClassMetricsCallback(tf.keras.callbacks.Callback):
    """Log per-class precision/recall and a confusion matrix at epoch end."""

    def __init__(self, val_ds: tf.data.Dataset, class_names: List[str], log_dir: Path):
        super().__init__()
        self.val_ds = val_ds
        self.class_names = class_names
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)

    def on_epoch_end(self, epoch: int, logs: dict | None = None):
        try:
            from sklearn.metrics import classification_report, confusion_matrix

            y_true = []
            y_pred = []
            for x, y in self.val_ds:
                pred = self.model.predict(x, verbose=0)
                y_true.extend(np.argmax(y.numpy(), axis=1))
                y_pred.extend(np.argmax(pred, axis=1))
            y_true = np.array(y_true)
            y_pred = np.array(y_pred)
            report = classification_report(
                y_true, y_pred, target_names=self.class_names, zero_division=0
            )
            cm = confusion_matrix(y_true, y_pred)
            out_path = self.log_dir / f"epoch_{epoch:03d}_metrics.txt"
            with open(out_path, "w") as f:
                f.write(f"Epoch {epoch}\\n\\n")
                f.write("Classification Report\\n")
                f.write("=====================\\n")
                f.write(report)
                f.write("\\n\\nConfusion Matrix\\n")
                f.write("================\\n")
                f.write("\\t" + "\\t".join(self.class_names) + "\\n")
                for i, row in enumerate(cm):
                    f.write(self.class_names[i] + "\\t" + "\\t".join(str(v) for v in row) + "\\n")
            print(f"\\n[Metrics] Saved per-class report to {out_path}")
        except Exception as exc:
            print(f"\\n[Metrics] Could not compute per-class metrics: {exc}")


def build_callbacks(
    exported_dir: Path,
    task: str,
    monitor: str = "val_loss",
    backup_dir: Path | None = None,
    val_ds: tf.data.Dataset | None = None,
    class_names: List[str] | None = None,
    checkpoint_monitor: str = "val_accuracy",
) -> List[tf.keras.callbacks.Callback]:
    """Return callbacks for training: early stop, LR reduction, checkpoints, resume backup.

    Includes:
      - BackupAndRestore: saves training state at epoch boundaries and resumes
        automatically on the next run if the process is interrupted.
      - ModelCheckpoint (best): saves the best weights seen so far.
      - ModelCheckpoint (latest): overwrites the latest epoch weights each epoch.
      - EarlyStopping + ReduceLROnPlateau.

    To force a fresh start, delete the backup directory before running.
    """
    exported_dir.mkdir(parents=True, exist_ok=True)
    if backup_dir is None:
        backup_dir = exported_dir / f"{task}_backup"
    backup_dir.mkdir(parents=True, exist_ok=True)

    callbacks: List[tf.keras.callbacks.Callback] = [
        tf.keras.callbacks.EarlyStopping(
            monitor=monitor,
            patience=10,
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor=monitor,
            factor=0.5,
            patience=5,
            min_lr=1e-7,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(exported_dir / f"{task}_best.keras"),
            monitor=checkpoint_monitor,
            save_best_only=True,
            verbose=1,
        ),
        tf.keras.callbacks.ModelCheckpoint(
            filepath=str(exported_dir / f"{task}_latest.keras"),
            save_best_only=False,
            save_freq="epoch",
            verbose=1,
        ),
        tf.keras.callbacks.BackupAndRestore(
            backup_dir=str(backup_dir),
            save_freq="epoch",
        ),
    ]
    if val_ds is not None and class_names is not None:
        callbacks.append(PerClassMetricsCallback(val_ds, class_names, exported_dir / f"{task}_metrics"))
    return callbacks


def write_training_summary(
    exported_dir: Path,
    task: str,
    config: dict,
    history: dict,
    test_metrics: dict,
) -> Path:
    """Write a JSON summary of the training run."""
    path = exported_dir / f"{task}_training_summary.json"
    summary = {
        "task": task,
        "config": config,
        "history": history,
        "test_metrics": test_metrics,
    }
    with open(path, "w") as f:
        json.dump(summary, f, indent=2)
    return path


def _attribute_labels_from_row(
    row: dict,
    class_to_attributes: dict,
    attribute_groups: dict,
) -> dict | None:
    """Return integer attribute label indices for each group, or None if invalid."""
    class_label = row.get("label")
    if class_label not in class_to_attributes:
        return None
    attrs = class_to_attributes[class_label]
    labels = {}
    for group_name, class_list in attribute_groups.items():
        group_class_to_idx = {name: idx for idx, name in enumerate(class_list)}
        attr_value = attrs.get(group_name)
        if attr_value is None or attr_value not in group_class_to_idx:
            return None
        labels[group_name] = group_class_to_idx[attr_value]
    return labels


def _parse_multi_task_image(
    path: str,
    labels: dict,
    attribute_groups: dict,
    image_size: Tuple[int, int],
    sample_weight: Optional[tf.Tensor] = None,
):
    """Parse image and one-hot encode each attribute group."""
    img = tf.io.read_file(path)
    img = tf.image.decode_jpeg(img, channels=3)
    img = tf.image.resize(img, image_size)
    img = tf.cast(img, tf.float32)
    # MobileNetV2 preprocessing: scale to [-1, 1].
    img = (img / 127.5) - 1.0
    label_tensors = {}
    for group_name, class_list in attribute_groups.items():
        idx = labels[group_name]
        label_tensors[group_name] = tf.one_hot(idx, depth=len(class_list))
    if sample_weight is not None:
        return img, label_tensors, sample_weight
    return img, label_tensors


def build_multi_task_dataset(
    manifest_path: Path,
    class_to_attributes: dict,
    attribute_groups: dict,
    image_size: List[int],
    batch_size: int,
    seed: int = 42,
    shuffle: bool = True,
    class_weights: Optional[Dict[str, Dict[int, float]]] = None,
) -> tf.data.Dataset:
    """Build a tf.data.Dataset for multi-task attribute classification.

    Each sample yields (image, {group_name: one_hot_tensor}) by default, or
    (image, {group_name: one_hot_tensor}, sample_weight) when class_weights is
    supplied. Using explicit sample weights avoids Keras class_weight key-type
    issues with multi-output models.
    """
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")

    rows = load_manifest(manifest_path)
    root = get_project_root()

    paths = []
    label_arrays: Dict[str, list] = {group_name: [] for group_name in attribute_groups}
    sample_weights: list = []
    for row in rows:
        labels = _attribute_labels_from_row(row, class_to_attributes, attribute_groups)
        if labels is None:
            continue
        paths.append(str(root / row["path"]))
        for group_name, idx in labels.items():
            label_arrays[group_name].append(idx)
        if class_weights:
            # Use geometric mean of per-attribute class weights. Multiplying
            # across six attribute heads produces a dynamic range of 10^4+,
            # which destabilizes training; the geometric mean keeps samples on
            # a comparable scale while still up-weighting rare classes.
            import math

            log_weights = []
            for group_name, idx in labels.items():
                group_cw = class_weights.get(group_name, {})
                w = group_cw.get(idx, 1.0)
                if w > 0:
                    log_weights.append(math.log(w))
            weight = math.exp(sum(log_weights) / len(log_weights)) if log_weights else 1.0
            sample_weights.append(weight)

    if not paths:
        raise ValueError(f"No valid multi-task samples found in {manifest_path}")

    image_size_tuple = tuple(image_size)

    if class_weights:
        ds = tf.data.Dataset.from_tensor_slices((paths, label_arrays, sample_weights))

        def parse_fn(p, l, w):
            return _parse_multi_task_image(p, l, attribute_groups, image_size_tuple, w)
    else:
        ds = tf.data.Dataset.from_tensor_slices((paths, label_arrays))

        def parse_fn(p, l):
            return _parse_multi_task_image(p, l, attribute_groups, image_size_tuple)

    if shuffle:
        buffer_size = min(len(paths), 10000)
        ds = ds.shuffle(buffer_size=buffer_size, seed=seed, reshuffle_each_iteration=True)

    ds = ds.map(parse_fn, num_parallel_calls=tf.data.AUTOTUNE)
    ds = ds.batch(batch_size)
    ds = ds.prefetch(tf.data.AUTOTUNE)
    return ds


def compute_attribute_class_weights(
    manifest_path: Path,
    class_to_attributes: dict,
    attribute_groups: dict,
) -> Dict[str, Dict[int, float]]:
    """Compute balanced class weights per attribute group from a manifest."""
    rows = load_manifest(manifest_path)
    group_counts: Dict[str, Counter] = {
        group_name: Counter() for group_name in attribute_groups
    }
    for row in rows:
        labels = _attribute_labels_from_row(row, class_to_attributes, attribute_groups)
        if labels is None:
            continue
        for group_name, idx in labels.items():
            group_counts[group_name][idx] += 1

    weights = {}
    for group_name, class_list in attribute_groups.items():
        counts = group_counts[group_name]
        total = sum(counts.values())
        n_classes = len(class_list)
        group_weights = {}
        for idx in range(n_classes):
            count = counts.get(idx, 0)
            if count > 0:
                group_weights[idx] = total / (n_classes * count)
        weights[group_name] = group_weights
    return weights


def save_attribute_label_map(
    exported_dir: Path,
    task: str,
    attribute_groups: dict,
    class_to_attributes: dict,
) -> Path:
    """Save a JSON label map for a multi-task attribute classifier."""
    path = exported_dir / f"{task}_attributes.json"
    group_class_to_index = {
        group_name: {name: idx for idx, name in enumerate(class_list)}
        for group_name, class_list in attribute_groups.items()
    }
    mapping = {
        "attribute_groups": attribute_groups,
        "class_to_attributes": class_to_attributes,
        "group_class_to_index": group_class_to_index,
    }
    with open(path, "w") as f:
        json.dump(mapping, f, indent=2)
    return path


def write_multi_task_training_summary(
    exported_dir: Path,
    task: str,
    config: dict,
    history: dict,
    test_metrics: dict,
) -> Path:
    """Write a JSON summary for a multi-task attribute training run."""
    path = exported_dir / f"{task}_training_summary.json"
    summary = {
        "task": task,
        "config": config,
        "history": history,
        "test_metrics": test_metrics,
    }
    with open(path, "w") as f:
        json.dump(summary, f, indent=2)
    return path
