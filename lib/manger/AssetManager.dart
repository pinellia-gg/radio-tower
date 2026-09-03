import 'package:flutter/material.dart';

class AssetManager {
  static AssetImage loadAssetImage(String path) {
    return AssetImage(path);
  }

  static Image loadImage(String path) {
    return Image(image: loadAssetImage(path));
  }
}
