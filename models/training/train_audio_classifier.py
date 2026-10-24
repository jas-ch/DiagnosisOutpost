"""Reusable training script for the cough audio classifier.

Intended to run in a private local training environment. The exported
TFLite model and label map are later copied to the Flutter assets.
"""

import argparse

import tensorflow as tf

from utils import (
    build_callbacks,
    build_dataset,
    compute_class_weights,
    convert_to_tflite,
    get_paths,
    load_config,
    save_label_map,
    set_seeds,
    write_training_summary,
)


def build_model(input_size: list, num_classes: int, model_name: str = "audio_cnn"):
    """Build a small CNN classifier for mel-spectrogram images."""
    if model_name != "audio_cnn":
        raise ValueError(f"Unsupported audio model: {model_name}")

    inputs = tf.keras.Input(shape=(input_size[0], input_size[1], 1))

    x = tf.keras.layers.Conv2D(32, 3, padding="same", activation=None)(inputs)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Activation("relu")(x)
    x = tf.keras.layers.MaxPooling2D()(x)

    x = tf.keras.layers.Conv2D(64, 3, padding="same", activation=None)(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Activation("relu")(x)
    x = tf.keras.layers.MaxPooling2D()(x)

    x = tf.keras.layers.Conv2D(128, 3, padding="same", activation=None)(x)
    x = tf.keras.layers.BatchNormalization()(x)
    x = tf.keras.layers.Activation("relu")(x)
    x = tf.keras.layers.MaxPooling2D()(x)

    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)

    model = tf.keras.Model(inputs, outputs, name="audio_cnn_classifier")
    return model


def train(config: dict, epochs: int | None = None, batch_size: int | None = None):
    """Train, validate, test, and export a cough audio classifier."""
    task = config["task"]
    classes = config["classes"]
    num_classes = len(classes)
    input_size = config["input_size"]
    batch_size = batch_size or config.get("batch_size", 32)
    epochs = epochs or config.get("epochs", 50)
    learning_rate = config.get("learning_rate", 0.0001)

    processed_dir, exported_dir = get_paths(task)

    print(f"Training {task} audio classifier")
    print(f"  classes: {classes}")
    print(f"  spectrogram size: {input_size}")
    print(f"  batch size: {batch_size}, epochs: {epochs}, lr: {learning_rate}")

    train_ds = build_dataset(
        processed_dir / "train_balanced.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="grayscale",
        shuffle=True,
    )
    val_ds = build_dataset(
        processed_dir / "val.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="grayscale",
        shuffle=False,
    )
    test_ds = build_dataset(
        processed_dir / "test.csv",
        class_names=classes,
        image_size=input_size,
        batch_size=batch_size,
        color_mode="grayscale",
        shuffle=False,
    )

    model = build_model(input_size, num_classes, model_name=config.get("model", "audio_cnn"))
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=learning_rate),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )
    model.summary()

    class_weight = compute_class_weights(processed_dir / "train_balanced.csv", classes)
    if class_weight:
        print(f"  class weights: {class_weight}")

    callbacks = build_callbacks(exported_dir, task, monitor="val_loss")

    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=epochs,
        callbacks=callbacks,
        class_weight=class_weight,
    )

    print("\nEvaluating on test set ...")
    test_loss, test_acc = model.evaluate(test_ds, verbose=1)
    test_metrics = {"loss": float(test_loss), "accuracy": float(test_acc)}
    print(f"Test loss: {test_loss:.4f}, Test accuracy: {test_acc:.4f}")

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
        history={k: [float(v) for v in vals] for k, vals in history.history.items()},
        test_metrics=test_metrics,
    )
    print(f"Saved training summary to {summary_path}")


def main():
    parser = argparse.ArgumentParser(description="Train an on-device audio classifier.")
    parser.add_argument("--config", required=True, help="Path to YAML config.")
    parser.add_argument("--epochs", type=int, default=None, help="Override epochs from config.")
    parser.add_argument("--batch-size", type=int, default=None, help="Override batch size.")
    args = parser.parse_args()

    set_seeds(42)
    config = load_config(args.config)
    train(config, epochs=args.epochs, batch_size=args.batch_size)


if __name__ == "__main__":
    main()
