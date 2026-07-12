import ARKit

/// ARKit's `ARFaceAnchor.blendShapes` is a dictionary keyed by
/// `ARBlendShapeLocation`. The engine's `blend[52]` array is in MediaPipe
/// face_blendshapes order, which is 1:1 with Apple's ARKit blendshape order.
/// Build the flat float array by iterating the known 52-order list.
let kARKitBlendShapeOrder: [ARFaceAnchor.BlendShapeLocation] = [
    .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight,
    .cheekPuff, .cheekSquintLeft, .cheekSquintRight,
    .eyeBlinkLeft, .eyeBlinkRight,
    .eyeLookDownLeft, .eyeLookDownRight, .eyeLookInLeft, .eyeLookInRight,
    .eyeLookOutLeft, .eyeLookOutRight, .eyeLookUpLeft, .eyeLookUpRight,
    .eyeSquintLeft, .eyeSquintRight, .eyeWideLeft, .eyeWideRight,
    .jawForward, .jawLeft, .jawRight, .jawOpen,
    .mouthClose, .mouthFunnel, .mouthPucker,
    .mouthRight, .mouthLeft,
    .mouthSmileLeft, .mouthSmileRight, .mouthFrownLeft, .mouthFrownRight,
    .mouthDimpleLeft, .mouthDimpleRight, .mouthStretchLeft, .mouthStretchRight,
    .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
    .mouthPressLeft, .mouthPressRight,
    .mouthLowerDownLeft, .mouthLowerDownRight,
    .mouthUpperUpLeft, .mouthUpperUpRight,
    .noseSneerLeft, .noseSneerRight,
    .tongueOut
]

func arkitBlendShapeArray(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> [Float] {
    var out = [Float](repeating: 0, count: kARKitBlendShapeOrder.count)
    for (index, key) in kARKitBlendShapeOrder.enumerated() {
        out[index] = blendShapes[key]?.floatValue ?? 0
    }
    return out
}
