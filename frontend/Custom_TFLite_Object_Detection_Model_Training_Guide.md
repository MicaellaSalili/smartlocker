# Custom TFLite Object Detection Model Training Guide

This guide walks you through training a custom TensorFlow Lite object detection model for the 'Live Detection' phase in your smart locker app. The goal is to detect objects such as `Locker_Frame`, `Package`, and `Waybill` using TensorFlow Lite Model Maker with the EfficientDet-Lite architecture for optimal mobile performance.

---

## 1. Dataset Preparation

### Image Collection
- Collect high-quality images representing each target class:
  - `Locker_Frame`: Images of the locker frame in various lighting and angles.
  - `Package`: Different package types, sizes, and placements.
  - `Waybill`: Waybills attached to packages, visible and clear.
- **Minimum recommended images:**
  - At least **500 images per class** for robust performance.
  - Ensure diversity in backgrounds, lighting, and object positions.

### Annotation
- Use annotation tools (e.g., [LabelImg](https://github.com/tzutalin/labelImg), [MakeSense.ai](https://www.makesense.ai/)) to label bounding boxes for each object:
  - Assign labels: `Locker_Frame`, `Package`, `Waybill`.
- Export annotations in Pascal VOC XML or COCO JSON format (Model Maker supports both).

### Data Balance
- Ensure each class is well-represented to avoid bias.
- If classes are imbalanced, consider data augmentation (flipping, rotation, brightness adjustment).

---

## 2. Environment Setup

### Required Python Libraries
- Python 3.7+
- [TensorFlow](https://www.tensorflow.org/) (>=2.5)
- [TensorFlow Lite Model Maker](https://www.tensorflow.org/lite/model_maker) (>=0.3.0)
- [Pillow](https://pypi.org/project/Pillow/) (for image processing)
- [matplotlib](https://matplotlib.org/) (for visualization)

#### Install with pip:
```bash
pip install tensorflow tensorflow-lite-model-maker pillow matplotlib
```

---

## 3. Training Steps

### Pseudo-code Structure
```python
import tensorflow as tf
from tflite_model_maker import object_detector
from tflite_model_maker.object_detector import DataLoader

# Step 1: Load and prepare the dataset
train_data = DataLoader.from_pascal_voc(
    images_dir='path/to/images',
    annotations_dir='path/to/annotations',
    label_map={1: 'Locker_Frame', 2: 'Package', 3: 'Waybill'}
)

# Step 2: Customize EfficientDet-Lite model
model = object_detector.create(
    train_data,
    model_spec=object_detector.EfficientDetLite0Spec(),  # Use Lite0 for speed, Lite2 for accuracy
    batch_size=16,
    epochs=50,
    validation_data=train_data.split(0.1)  # 10% for validation
)

# Step 3: Evaluate model performance
metrics = model.evaluate()
print('mAP:', metrics['map'])

# Step 4: Visualize predictions (optional)
model.predict('path/to/test/image.jpg')
```

#### Notes:
- Adjust `batch_size` and `epochs` based on dataset size and hardware.
- Use `EfficientDetLite0Spec` for fastest inference; try `Lite1` or `Lite2` for higher accuracy if needed.
- Monitor mAP (mean Average Precision) for detection quality.

---

## 4. Model Export & Integration

### Export the Model
```python
model.export(export_dir='exported-model', tflite_filename='detect.tflite')
```
- The exported `detect.tflite` file will be in the `exported-model` directory.

### Integration in Flutter
- Replace the ML Kit logic in `tflite_processor.dart` with TFLite inference:
  - Use [tflite_flutter](https://pub.dev/packages/tflite_flutter) to load and run the model.
  - Update the detection pipeline to use the new classes (`Locker_Frame`, `Package`, `Waybill`).
  - Parse the output tensor to extract bounding boxes and class labels.

#### Example (Dart):
```dart
final interpreter = await Interpreter.fromAsset('detect.tflite');
// Preprocess camera image, run inference, and postprocess results
```
- See your existing `tflite_processor.dart` for integration points.

---

## References
- [TensorFlow Lite Model Maker Object Detection](https://www.tensorflow.org/lite/model_maker/object_detection/overview)
- [EfficientDet-Lite Models](https://www.tensorflow.org/lite/performance/object_detection)
- [tflite_flutter Dart Package](https://pub.dev/packages/tflite_flutter)
- [LabelImg Annotation Tool](https://github.com/tzutalin/labelImg)

---

**By following this guide, you can train and deploy a custom TFLite object detection model optimized for your smart locker app's live detection phase.**
