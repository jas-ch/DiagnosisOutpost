"""Reusable training script for image classifiers (rash, tongue, wound, face).

Intended to run in a private local training environment. The exported
TFLite model and label map are later copied to the Flutter assets.
"""

import argparse
import json
import shutil
from collections import Counter
from pathlib import Path

import numpy as np
import tensorflow as tf

from utils import (
    build_callbacks,
    build_dataset,
    build_multi_task_dataset,
    compute_attribute_class_weights,
    compute_class_weights,
    convert_to_tflite,
    get_paths,
    load_config,
    save_attribute_label_map,
    save_label_map,
    set_seeds,
    write_multi_task_training_summary,
    write_training_summary,
)


def build_model(
    input_size: list,
    num_classes: int,
    model_name: str = "mobilenetv2",
    weights: str = "imagenet",
):
    """Build a MobileNetV2-based image classifier."""
    if model_name != "mobilenetv2":
        raise ValueError(f"Unsupported image model: {model_name}")

    input_shape = (input_size[0], input_size[1], 3)

    if weights == "imagenet":
        try:
            base = tf.keras.applications.MobileNetV2(
                input_shape=input_shape,
                include_top=False,
                weights="imagenet",
                name="mobilenetv2_base",
            )
        except Exception as exc:
            print(
                f"\nWarning: could not load ImageNet weights ({exc}). "
                "Falling back to random initialization. For offline transfer learning, "
                "pre-cache the weights or run with --weights none.\n"
            )
            base = tf.keras.applications.MobileNetV2(
                input_shape=input_shape,
                include_top=False,
                weights=None,
                name="mobilenetv2_base",
            )
    elif weights == "none":
        base = tf.keras.applications.MobileNetV2(
            input_shape=input_shape,
            include_top=False,
            weights=None,
            name="mobilenetv2_base",
        )
    else:
        # Local weights file path (no-top MobileNetV2 weights).
        base = tf.keras.applications.MobileNetV2(
            input_shape=input_shape,
            include_top=False,
            weights=None,
            name="mobilenetv2_base",
        )
        base.load_weights(weights)

    # Freeze the backbone for the feature-extraction phase.
    base.trainable = False

    inputs = tf.keras.Input(shape=input_shape)
    x = base(inputs, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)

    model = tf.keras.Model(inputs, outputs, name=f"{model_name}_classifier")
    return model


def build_multi_task_model(
    input_size: list,
    attribute_groups: dict,
    weights: str = "imagenet",
):
    """Build a MobileNetV2-based multi-task attribute classifier.

    Each attribute group gets its own softmax classification head.
    """
    input_shape = (input_size[0], input_size[1], 3)

    if weights == "imagenet":
        try:
            base = tf.keras.applications.MobileNetV2(
                input_shape=input_shape,
                include_top=False,
                weights="imagenet",
                name="mobilenetv2_base",
            )
        except Exception as exc:
            print(
                f"\nWarning: could not load ImageNet weights ({exc}). "
                "Falling back to random initialization. For offline transfer learning, "
                "pre-cache the weights or run with --weights none.\n"
            )
            base = tf.keras.applications.MobileNetV2(
                input_shape=input_shape,
                include_top=False,
                weights=None,
                name="mobilenetv2_base",
            )
    elif weights == "none":
        base = tf.keras.applications.MobileNetV2(
            input_shape=input_shape,
            include_top=False,
            weights=None,
            name="mobilenetv2_base",
        )
    else:
        base = tf.keras.applications.MobileNetV2(
            input_shape=input_shape,
            include_top=False,
            weights=None,
            name="mobilenetv2_base",
        )
        base.load_weights(weights)

    # Freeze the backbone for the feature-extraction phase.
    base.trainable = False

    inputs = tf.keras.Input(shape=input_shape)
    x = base(inputs, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)

    outputs = {}
    for group_name, class_list in attribute_groups.items():
        outputs[group_name] = tf.keras.layers.Dense(
            len(class_list),
            activation="softmax",
            name=group_name,
        )(x)

    model = tf.keras.Model(inputs, outputs, name="mobilenetv2_multi_task_attributes")
    return model


def unfreeze_top_layers(model: tf.keras.Model, fine_tune_layers: int):
    """Unfreeze the top N layers of the MobileNetV2 backbone."""
    base = model.get_layer("mobilenetv2_base")
    if base is None:
        return

    max_layers = len(base.layers)
    layers_to_unfreeze = min(fine_tune_layers, max_layers)

    base.trainable = True
    for layer in base.layers[: max_layers - layers_to_unfreeze]:
        layer.trainable = False
    for layer in base.layers[max_layers - layers_to_unfreeze :]:
        layer.trainable = True

    print(
        f"\n[Fine-tuning] Unfroze top {layers_to_unfreeze} backbone layers "
        f"({max_layers - layers_to_unfreeze} remain frozen)."
    )


def _has_backup(backup_dir: Path) -> bool:
    return backup_dir.exists() and any(backup_dir.iterdir())


def _combine_histories(history1: dict | None, history2: dict) -> dict:
    if history1 is None:
        return history2
    combined = {}
    for key in history2.keys():
        combined[key] = list(history1.get(key, [])) + list(history2[key])
    return combined


def _evaluate_per_class(model: tf.keras.Model, ds: tf.data.Dataset, class_names: list) -> dict:
    """Return per-class accuracy and overall metrics."""
    y_true = []
    y_pred = []
    for x, y in ds:
        pred = model.predict(x, verbose=0)
        y_true.extend(np.argmax(y.numpy(), axis=1))
        y_pred.extend(np.argmax(pred, axis=1))
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)
    overall = float(np.mean(y_true == y_pred))
    per_class = {}
    for idx, name in enumerate(class_names):
        mask = y_true == idx
        if mask.sum() > 0:
            per_class[name] = float(np.mean(y_pred[mask] == idx))
        else:
            per_class[name] = None
    pred_dist = dict(Counter(int(p) for p in y_pred))
    return {
        "accuracy": overall,
        "per_class_accuracy": per_class,
        "predicted_distribution": {class_names[i]: pred_dist.get(i, 0) for i in range(len(class_names))},
    }


def _verify_not_collapsed(model: tf.keras.Model, ds: tf.data.Dataset, class_names: list) -> bool:
    """Return True if the model predicts more than one class."""
    preds = []
    for x, _ in ds.take(10):
        p = model.predict(x, verbose=0)
        preds.extend(np.argmax(p, axis=1).tolist())
    unique = set(preds)
    print(f"[Verify] predicted classes in sample: {sorted(unique)}")
    if len(unique) <= 1:
        print("[Verify] WARNING: model appears collapsed to a single class!")
        return False
    return True


def _evaluate_multi_task(model: tf.keras.Model, ds: tf.data.Dataset, attribute_groups: dict) -> dict:
    """Return per-group accuracy and mean accuracy for a multi-task model."""
    group_true: Dict[str, list] = {group_name: [] for group_name in attribute_groups}
    group_pred: Dict[str, list] = {group_name: [] for group_name in attribute_groups}

    for x, y_true in ds:
        y_pred = model.predict(x, verbose=0)
        for group_name in attribute_groups:
            true_labels = np.argmax(y_true[group_name].numpy(), axis=1)
            pred_labels = np.argmax(y_pred[group_name], axis=1)
            group_true[group_name].extend(true_labels.tolist())
            group_pred[group_name].extend(pred_labels.tolist())

    per_group = {}
    accuracies = []
    for group_name in attribute_groups:
        true_arr = np.array(group_true[group_name])
        pred_arr = np.array(group_pred[group_name])
        acc = float(np.mean(true_arr == pred_arr))
        per_group[group_name] = {
            "accuracy": acc,
            "num_samples": int(len(true_arr)),
        }
        accuracies.append(acc)

    return {
        "per_group_accuracy": per_group,
        "mean_accuracy": float(np.mean(accuracies)),
    }


def _focal_loss(gamma: float = 2.0, alpha: float | None = None):
    """Return a multi-class focal loss function."""
    def loss(y_true, y_pred):
        # Clip predictions for numerical stability.
        epsilon = tf.keras.backend.epsilon()
        y_pred = tf.clip_by_value(y_pred, epsilon, 1.0 - epsilon)
        # Cross-entropy.
        ce = -y_true * tf.math.log(y_pred)
        # Focal weight: (1 - p_t)^gamma
        p_t = tf.reduce_sum(y_true * y_pred, axis=-1, keepdims=True)
        weight = tf.pow(1.0 - p_t, gamma)
        fl = weight * ce
        if alpha is not None:
            fl = alpha * fl
        return tf.reduce_mean(tf.reduce_sum(fl, axis=-1))
    return loss


def train(
    config: dict,
    epochs: int | None = None,
    batch_size: int | None = None,
    weights: str = "imagenet",
):
    """Train, validate, test, and export an image classifier."""
    task = config["task"]
    classes = config["classes"]
    num_classes = len(classes)
    input_size = config["input_size"]
    batch_size = batch_size or config.get("batch_size", 32)
    epochs = epochs or config.get("epochs", 50)
    learning_rate = config.get("learning_rate", 0.0001)
    use_focal_loss = config.get("use_focal_loss", False)
    focal_gamma = config.get("focal_gamma", 2.0)
    loss_fn = _focal_loss(gamma=focal_gamma) if use_focal_loss else "categorical_crossentropy"
    print(f"  loss function: {'focal loss (gamma=' + str(focal_gamma) + ')' if use_focal_loss else 'categorical_crossentropy'}")

    fine_tune_epochs = config.get("fine_tune_epochs", max(1, epochs // 2))
    fine_tune_lr = config.get("fine_tune_learning_rate", learning_rate / 10.0)
    fine_tune_layers = config.get("fine_tune_layers", 30)
    total_epochs = epochs + fine_tune_epochs

    processed_dir, exported_dir = get_paths(task)
    phase1_backup = exported_dir / f"{task}_backup_phase1"
    phase2_backup = exported_dir / f"{task}_backup_phase2"

    print(f"Training {task} image classifier")
    print(f"  classes: {classes}")
    print(f"  input size: {input_size}")
    print(f"  batch size: {batch_size}")
    print(f"  phase 1 epochs: {epochs}, lr: {learning_rate}")
    print(f"  fine-tune epochs: {fine_tune_epochs}, lr: {fine_tune_lr}, layers: {fine_tune_layers}")
    print(f"  total epochs: {total_epochs}")
    print(f"  backbone weights: {weights}")
    print(f"  phase1 backup: {phase1_backup}")
    print(f"  phase2 backup: {phase2_backup}")

    class_weight = compute_class_weights(processed_dir / "train_balanced.csv", classes)
    if class_weight:
        print(f"  class weights: {class_weight}")

    train_ds = build_dataset(
        processed_dir / "train_balanced.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="rgb",
        shuffle=True,
    )
    val_ds = build_dataset(
        processed_dir / "val.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="rgb",
        shuffle=False,
    )
    test_ds = build_dataset(
        processed_dir / "test.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="rgb",
        shuffle=False,
    )

    model = build_model(
        input_size,
        num_classes,
        model_name=config.get("model", "mobilenetv2"),
        weights=weights,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
        loss=loss_fn,
        metrics=["accuracy"],
    )
    model.summary()

    history1 = None
    if not _has_backup(phase2_backup):
        print("\n=== Phase 1: frozen backbone ===")
        callbacks_phase1 = build_callbacks(
            exported_dir,
            task,
            monitor="val_loss",
            backup_dir=phase1_backup,
            val_ds=val_ds,
            class_names=classes,
        )
        history1 = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=epochs,
            class_weight=class_weight,
            callbacks=callbacks_phase1,
        )

        # Prepare for fine-tuning.
        unfreeze_top_layers(model, fine_tune_layers)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=fine_tune_lr),
            loss=loss_fn,
            metrics=["accuracy"],
        )
        # Remove phase 1 backup so a restart resumes from phase 2.
        if phase1_backup.exists():
            shutil.rmtree(phase1_backup)
    else:
        print("\n=== Resuming phase 2 from existing backup ===")
        unfreeze_top_layers(model, fine_tune_layers)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=fine_tune_lr),
            loss=loss_fn,
            metrics=["accuracy"],
        )

    print("\n=== Phase 2: fine-tuning ===")
    callbacks_phase2 = build_callbacks(
        exported_dir,
        task,
        monitor="val_loss",
        backup_dir=phase2_backup,
        val_ds=val_ds,
        class_names=classes,
    )
    history2 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=total_epochs,
        class_weight=class_weight,
        callbacks=callbacks_phase2,
    )

    history = _combine_histories(
        history1.history if history1 else None,
        history2.history,
    )

    print("\nEvaluating on test set ...")
    test_loss, test_acc = model.evaluate(test_ds, verbose=1)
    test_metrics = {"loss": float(test_loss), "accuracy": float(test_acc)}
    print(f"Test loss: {test_loss:.4f}, Test accuracy: {test_acc:.4f}")

    print("\nPer-class test metrics:")
    per_class_metrics = _evaluate_per_class(model, test_ds, classes)
    print(f"  overall accuracy: {per_class_metrics['accuracy']:.4f}")
    for name, acc in per_class_metrics["per_class_accuracy"].items():
        print(f"  {name}: {acc if acc is None else f'{acc:.4f}'}")

    if not _verify_not_collapsed(model, test_ds, classes):
        print("\nWARNING: model collapsed. Check data quality and hyperparameters.")

    keras_path = exported_dir / f"{task}_classifier.keras"
    model.save(keras_path)
    print(f"Saved Keras model to {keras_path}")

    print("Converting to TFLite ...")
    quantize = config.get("quantize", False)
    tflite_model = convert_to_tflite(
        model,
        representative_ds=test_ds if quantize else None,
        quantize=quantize,
    )
    tflite_path = exported_dir / f"{task}_classifier.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"Saved {'INT8' if quantize else 'float32'} TFLite model to {tflite_path}")

    label_path = save_label_map(exported_dir, task, classes)
    print(f"Saved label map to {label_path}")

    summary_path = write_training_summary(
        exported_dir,
        task,
        config,
        history={k: [float(v) for v in vals] for k, vals in history.items()},
        test_metrics={**test_metrics, **per_class_metrics},
    )
    print(f"Saved training summary to {summary_path}")


def train_multi_task(
    config: dict,
    epochs: int | None = None,
    batch_size: int | None = None,
    weights: str = "imagenet",
):
    """Train, validate, test, and export a multi-task attribute classifier."""
    task = config["task"]
    attribute_groups = config["attribute_groups"]
    class_to_attributes = config["class_to_attributes"]
    input_size = config["input_size"]
    batch_size = batch_size or config.get("batch_size", 32)
    epochs = epochs or config.get("epochs", 50)
    learning_rate = config.get("learning_rate", 0.0001)
    fine_tune_epochs = config.get("fine_tune_epochs", max(1, epochs // 2))
    fine_tune_lr = config.get("fine_tune_learning_rate", learning_rate / 10.0)
    fine_tune_layers = config.get("fine_tune_layers", 30)
    total_epochs = epochs + fine_tune_epochs

    processed_dir, exported_dir = get_paths(task)
    phase1_backup = exported_dir / f"{task}_backup_phase1"
    phase2_backup = exported_dir / f"{task}_backup_phase2"

    print(f"Training {task} multi-task attribute classifier")
    print(f"  attribute groups: {list(attribute_groups.keys())}")
    print(f"  input size: {input_size}")
    print(f"  batch size: {batch_size}")
    print(f"  phase 1 epochs: {epochs}, lr: {learning_rate}")
    print(f"  fine-tune epochs: {fine_tune_epochs}, lr: {fine_tune_lr}, layers: {fine_tune_layers}")
    print(f"  total epochs: {total_epochs}")
    print(f"  backbone weights: {weights}")
    print(f"  phase1 backup: {phase1_backup}")
    print(f"  phase2 backup: {phase2_backup}")

    attribute_class_weights = compute_attribute_class_weights(
        processed_dir / "train_balanced.csv",
        class_to_attributes,
        attribute_groups,
    )
    if attribute_class_weights:
        print(f"  attribute class weights: {attribute_class_weights}")

    train_ds = build_multi_task_dataset(
        processed_dir / "train_balanced.csv",
        class_to_attributes,
        attribute_groups,
        image_size=input_size,
        batch_size=batch_size,
        shuffle=True,
        class_weights=attribute_class_weights,
    )
    val_ds = build_multi_task_dataset(
        processed_dir / "val.csv",
        class_to_attributes,
        attribute_groups,
        image_size=input_size,
        batch_size=batch_size,
        shuffle=False,
    )
    test_ds = build_multi_task_dataset(
        processed_dir / "test.csv",
        class_to_attributes,
        attribute_groups,
        image_size=input_size,
        batch_size=batch_size,
        shuffle=False,
    )

    model = build_multi_task_model(
        input_size,
        attribute_groups,
        weights=weights,
    )
    loss_dict = {group_name: "categorical_crossentropy" for group_name in attribute_groups}
    metrics_dict = {group_name: "accuracy" for group_name in attribute_groups}
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
        loss=loss_dict,
        metrics=metrics_dict,
    )
    model.summary()

    history1 = None
    if not _has_backup(phase2_backup):
        print("\n=== Phase 1: frozen backbone ===")
        callbacks_phase1 = build_callbacks(
            exported_dir,
            task,
            monitor="val_loss",
            backup_dir=phase1_backup,
            checkpoint_monitor="val_loss",
        )
        history1 = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=epochs,
            callbacks=callbacks_phase1,
        )

        # Prepare for fine-tuning.
        unfreeze_top_layers(model, fine_tune_layers)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=fine_tune_lr),
            loss=loss_dict,
            metrics=metrics_dict,
        )
        # Remove phase 1 backup so a restart resumes from phase 2.
        if phase1_backup.exists():
            shutil.rmtree(phase1_backup)
    else:
        print("\n=== Resuming phase 2 from existing backup ===")
        unfreeze_top_layers(model, fine_tune_layers)
        model.compile(
            optimizer=tf.keras.optimizers.Adam(learning_rate=fine_tune_lr),
            loss=loss_dict,
            metrics=metrics_dict,
        )

    print("\n=== Phase 2: fine-tuning ===")
    callbacks_phase2 = build_callbacks(
        exported_dir,
        task,
        monitor="val_loss",
        backup_dir=phase2_backup,
        checkpoint_monitor="val_loss",
    )
    history2 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=total_epochs,
        callbacks=callbacks_phase2,
    )

    history = _combine_histories(
        history1.history if history1 else None,
        history2.history,
    )

    print("\nEvaluating on test set ...")
    test_evaluation = model.evaluate(test_ds, verbose=1, return_dict=True)
    test_metrics = {k: float(v) for k, v in test_evaluation.items()}
    print(f"Test metrics: {test_metrics}")

    print("\nPer-attribute test metrics:")
    per_group_metrics = _evaluate_multi_task(model, test_ds, attribute_groups)
    for group_name, metrics in per_group_metrics["per_group_accuracy"].items():
        print(f"  {group_name}: {metrics['accuracy']:.4f}")
    print(f"  mean accuracy: {per_group_metrics['mean_accuracy']:.4f}")

    keras_path = exported_dir / f"{task}_classifier.keras"
    model.save(keras_path)
    print(f"Saved Keras model to {keras_path}")

    print("Converting to TFLite ...")
    quantize = config.get("quantize", False)
    tflite_model = convert_to_tflite(
        model,
        representative_ds=test_ds if quantize else None,
        quantize=quantize,
    )
    tflite_path = exported_dir / f"{task}_classifier.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_model)
    print(f"Saved {'INT8' if quantize else 'float32'} TFLite model to {tflite_path}")

    attribute_label_path = save_attribute_label_map(
        exported_dir,
        task,
        attribute_groups,
        class_to_attributes,
    )
    print(f"Saved attribute label map to {attribute_label_path}")

    tongue_evidence_rules = {
        "attribute_to_disease_evidence": {
            "scarlet_fever": [
                {"shape_features": "red_dots_strawberry", "score": 0.40},
                {"body_color": "red", "coating_color": "yellow", "score": 0.30},
            ],
            "kawasaki": [
                {"shape_features": "red_dots_strawberry", "score": 0.30},
                {"body_color": "red", "score": 0.10},
            ],
            "severe_pneumonia": [
                {"body_color": "purple_cyanotic", "score": 0.50},
            ],
            "covid_severe": [
                {"body_color": "purple_cyanotic", "score": 0.30},
                {"coating_color": "gray_black", "score": 0.20},
            ],
            "active_infection": [
                {"body_color": "red", "coating_color": "yellow", "score": 0.30},
                {"coating_texture": "thick", "score": 0.10},
            ],
            "dehydration_sepsis": [
                {"coating_color": "gray_black", "score": 0.35},
                {"moisture": "dry", "body_color": "red", "score": 0.15},
            ],
        },
        "wellness_patterns": [
            {"attributes": {"body_color": "pale", "coating_color": "none_normal"}, "pattern": "Qi / Yang deficiency", "suggestions": ["Warm cooked foods", "Ginger tea", "Rest", "Avoid cold/raw foods"]},
            {"attributes": {"body_color": "red", "coating_color": "yellow"}, "pattern": "Heat / toxin pattern", "suggestions": ["Cooling fluids", "Cucumber/watermelon", "Avoid alcohol/spicy"]},
            {"attributes": {"body_color": "purple_cyanotic", "moisture": "dry"}, "pattern": "Blood stasis / dehydration", "suggestions": ["Increase hydration", "Seek medical review if lips/nails also blue"]},
            {"attributes": {"shape_features": "fissured", "body_color": "red"}, "pattern": "Yin deficiency", "suggestions": ["Nourishing soups", "Pear", "Avoid late nights"]},
            {"attributes": {"shape_features": "swollen_toothmarked"}, "pattern": "Damp retention", "suggestions": ["Reduce greasy/sweet foods", "Light exercise"]},
            {"attributes": {"shape_features": "black_hairy"}, "pattern": "Oral dysbiosis / fungal overgrowth", "suggestions": ["Oral hygiene", "Probiotics", "Avoid smoking"]},
            {"attributes": {"coating_integrity": "peeled_geographic"}, "pattern": "Immune stress / Yin deficiency", "suggestions": ["Balanced diet", "Stress reduction", "Monitor"]},
            {"attributes": {"body_color": "pale", "shape_features": "fissured"}, "pattern": "Qi + Yin deficiency", "suggestions": ["Warm nourishing foods", "Adequate sleep"]},
        ],
    }
    evidence_path = exported_dir / "tongue_evidence_rules.json"
    with open(evidence_path, "w") as f:
        json.dump(tongue_evidence_rules, f, indent=2)
    print(f"Saved tongue evidence rules to {evidence_path}")

    summary_path = write_multi_task_training_summary(
        exported_dir,
        task,
        config,
        history={k: [float(v) for v in vals] for k, vals in history.items()},
        test_metrics={**test_metrics, **per_group_metrics},
    )
    print(f"Saved training summary to {summary_path}")


def main():
    parser = argparse.ArgumentParser(description="Train an on-device image classifier.")
    parser.add_argument("--config", required=True, help="Path to YAML config.")
    parser.add_argument("--epochs", type=int, default=None, help="Override epochs from config.")
    parser.add_argument("--batch-size", type=int, default=None, help="Override batch size.")
    parser.add_argument(
        "--weights",
        default="imagenet",
        help="Backbone weights: 'imagenet', 'none', or path to a local weights file.",
    )
    args = parser.parse_args()

    set_seeds(42)
    config = load_config(args.config)
    if config.get("classifier_type") == "multi_task_attributes":
        train_multi_task(
            config,
            epochs=args.epochs,
            batch_size=args.batch_size,
            weights=args.weights,
        )
    else:
        train(
            config,
            epochs=args.epochs,
            batch_size=args.batch_size,
            weights=args.weights,
        )


if __name__ == "__main__":
    main()
