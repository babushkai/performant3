#!/usr/bin/env python3
"""
YOLOv8 Training Script for Performant3
Communicates progress via JSON-line protocol on stdout
"""

import json
import sys
import os
import time
import argparse
from pathlib import Path

def emit(event_type: str, **kwargs):
    """Emit a JSON event to stdout for the Swift app to consume."""
    event = {"type": event_type, **kwargs}
    print(json.dumps(event), flush=True)

def log(level: str, message: str):
    """Emit a log event."""
    emit("log", level=level, message=message)

def progress(epoch: int, total_epochs: int, step: int = None, total_steps: int = None):
    """Emit a progress event."""
    emit("progress", epoch=epoch, totalEpochs=total_epochs, step=step, totalSteps=total_steps)

def metric(epoch: int, loss: float, accuracy: float = None, step: int = None, **extra):
    """Emit a metric event."""
    data = {"epoch": epoch, "loss": loss}
    if accuracy is not None:
        data["accuracy"] = accuracy
    if step is not None:
        data["step"] = step
    data.update(extra)
    emit("metric", **data)

def checkpoint(path: str, epoch: int):
    """Emit a checkpoint saved event."""
    emit("checkpoint", path=path, epoch=epoch)

def completed(final_loss: float, final_accuracy: float, duration: float):
    """Emit training completed event."""
    emit("completed", finalLoss=final_loss, finalAccuracy=final_accuracy, duration=duration)

def error(message: str):
    """Emit an error event."""
    emit("error", message=message)

def train_yolov8(
    model_variant: str = "yolov8n",
    dataset: str = "coco128",
    epochs: int = 100,
    batch_size: int = 16,
    image_size: int = 640,
    learning_rate: float = 0.01,
    output_dir: str = "runs/detect",
    resume: bool = False,
    device: str = "mps"  # Use Metal Performance Shaders on Mac
):
    """Train YOLOv8 model with Ultralytics."""

    try:
        from ultralytics import YOLO
        from ultralytics.utils import LOGGER
        import logging

        # Suppress ultralytics default logging (we'll emit our own)
        LOGGER.setLevel(logging.WARNING)

    except ImportError:
        error("Ultralytics not installed. Run: pip install ultralytics")
        sys.exit(1)

    start_time = time.time()
    log("info", f"Initializing YOLOv8 training...")
    log("info", f"Model: {model_variant}, Dataset: {dataset}, Epochs: {epochs}")
    log("info", f"Batch size: {batch_size}, Image size: {image_size}, LR: {learning_rate}")
    log("info", f"Device: {device}")

    try:
        # Load model
        if resume and os.path.exists(f"{output_dir}/weights/last.pt"):
            log("info", "Resuming from last checkpoint...")
            model = YOLO(f"{output_dir}/weights/last.pt")
        else:
            log("info", f"Loading pretrained {model_variant} model...")
            model = YOLO(f"{model_variant}.pt")

        # Custom callback to emit progress
        def on_train_epoch_end(trainer):
            epoch = trainer.epoch + 1
            metrics = trainer.metrics

            # Extract metrics
            box_loss = float(metrics.get("train/box_loss", 0))
            cls_loss = float(metrics.get("train/cls_loss", 0))
            dfl_loss = float(metrics.get("train/dfl_loss", 0))
            total_loss = box_loss + cls_loss + dfl_loss

            # mAP as "accuracy" for object detection
            map50 = float(metrics.get("metrics/mAP50(B)", 0))
            map50_95 = float(metrics.get("metrics/mAP50-95(B)", 0))

            metric(
                epoch=epoch,
                loss=total_loss,
                accuracy=map50,
                mAP50=map50,
                mAP50_95=map50_95,
                box_loss=box_loss,
                cls_loss=cls_loss,
                dfl_loss=dfl_loss
            )

            progress(epoch=epoch, total_epochs=epochs)

            log("info", f"Epoch {epoch}/{epochs} - Loss: {total_loss:.4f}, mAP50: {map50:.4f}, mAP50-95: {map50_95:.4f}")

        def on_train_batch_end(trainer):
            # Emit batch progress periodically
            if trainer.batch % 10 == 0:
                progress(
                    epoch=trainer.epoch + 1,
                    total_epochs=epochs,
                    step=trainer.batch,
                    total_steps=len(trainer.train_loader)
                )

        def on_model_save(trainer):
            save_dir = trainer.save_dir
            checkpoint(path=str(save_dir / "weights" / "best.pt"), epoch=trainer.epoch + 1)

        # Add callbacks
        model.add_callback("on_train_epoch_end", on_train_epoch_end)
        model.add_callback("on_train_batch_end", on_train_batch_end)
        model.add_callback("on_model_save", on_model_save)

        # Start training
        log("info", "Starting training...")

        results = model.train(
            data=dataset,
            epochs=epochs,
            batch=batch_size,
            imgsz=image_size,
            lr0=learning_rate,
            device=device,
            project=output_dir,
            name="train",
            exist_ok=True,
            verbose=False,
            plots=True,
            patience=0  # Disable early stopping - train all epochs
        )

        # Training completed
        duration = time.time() - start_time
        final_metrics = results.results_dict if hasattr(results, 'results_dict') else {}
        final_map50 = float(final_metrics.get("metrics/mAP50(B)", 0))
        final_loss = float(final_metrics.get("train/box_loss", 0) +
                          final_metrics.get("train/cls_loss", 0) +
                          final_metrics.get("train/dfl_loss", 0))

        log("info", f"Training completed in {duration:.1f}s")
        log("info", f"Final mAP50: {final_map50:.4f}")

        # Emit final checkpoint location
        best_weights = Path(output_dir) / "train" / "weights" / "best.pt"
        if best_weights.exists():
            checkpoint(path=str(best_weights), epoch=epochs)

        completed(final_loss=final_loss, final_accuracy=final_map50, duration=duration)

    except KeyboardInterrupt:
        log("warning", "Training interrupted by user")
        sys.exit(0)
    except Exception as e:
        error(f"Training failed: {str(e)}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="Train YOLOv8 model")
    parser.add_argument("--model", type=str, default="yolov8n",
                        choices=["yolov8n", "yolov8s", "yolov8m", "yolov8l", "yolov8x"],
                        help="YOLOv8 model variant")
    parser.add_argument("--dataset", type=str, default="coco128",
                        help="Dataset name or path to data.yaml")
    parser.add_argument("--epochs", type=int, default=100, help="Number of epochs")
    parser.add_argument("--batch-size", type=int, default=16, help="Batch size")
    parser.add_argument("--image-size", type=int, default=640, help="Image size")
    parser.add_argument("--learning-rate", type=float, default=0.01, help="Learning rate")
    parser.add_argument("--output-dir", type=str, default="runs/detect", help="Output directory")
    parser.add_argument("--resume", action="store_true", help="Resume training from last checkpoint")
    parser.add_argument("--device", type=str, default="mps",
                        help="Device (mps for Mac GPU, cpu, or cuda:0)")

    args = parser.parse_args()

    train_yolov8(
        model_variant=args.model,
        dataset=args.dataset,
        epochs=args.epochs,
        batch_size=args.batch_size,
        image_size=args.image_size,
        learning_rate=args.learning_rate,
        output_dir=args.output_dir,
        resume=args.resume,
        device=args.device
    )

if __name__ == "__main__":
    main()
