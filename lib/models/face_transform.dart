/// The two directions supported by the online face transform.
///
/// The user picks a direction explicitly. Sketchify does not try to infer
/// someone's gender from a photo.
enum FaceTransformDirection { feminize, masculinize }

extension FaceTransformDirectionX on FaceTransformDirection {
  /// Human-readable label used in progress and error messages.
  String get label => switch (this) {
    FaceTransformDirection.feminize => 'Feminize',
    FaceTransformDirection.masculinize => 'Masculinize',
  };

  /// The value sent to the proxy as `?direction=`.
  String get wireName => name;
}
