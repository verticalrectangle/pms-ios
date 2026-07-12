import ARKit

/// ARKit's `ARFaceAnchor.blendShapes` is a dictionary keyed by
/// `ARBlendShapeLocation`. The engine's `blend[52]` array is in MediaPipe
/// face_blendshapes order: `_neutral` at index 0, then the ARKit-style
/// coefficients ALPHABETICALLY, without tongueOut. This is NOT Apple's own
/// grouping — the previous list shipped Apple doc order with no `_neutral`
/// slot, so on the ARKit tier the engine read eyeBlinkRight as "blink left"
/// and eyeLookDownLeft as "blink right": every blendshape-driven behavior
/// (iris blink fade, jaw/smile-driven effects) got the wrong signal.
/// Keep 1:1 with the FB_ indices in the engine's face_track.h
/// (eyeBlinkLeft = 9, eyeLook* = 11-18, jawOpen = 25, mouthSmileLeft = 44).
let kMPBlendShapeOrder: [ARFaceAnchor.BlendShapeLocation?] = [
    nil,  // 0: _neutral — no ARKit equivalent, stays 0
    .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight,
    .cheekPuff, .cheekSquintLeft, .cheekSquintRight,
    .eyeBlinkLeft, .eyeBlinkRight,                       // 9, 10
    .eyeLookDownLeft, .eyeLookDownRight, .eyeLookInLeft, .eyeLookInRight,
    .eyeLookOutLeft, .eyeLookOutRight, .eyeLookUpLeft, .eyeLookUpRight,
    .eyeSquintLeft, .eyeSquintRight, .eyeWideLeft, .eyeWideRight,
    .jawForward, .jawLeft, .jawOpen, .jawRight,          // 23-26
    .mouthClose, .mouthDimpleLeft, .mouthDimpleRight,
    .mouthFrownLeft, .mouthFrownRight, .mouthFunnel, .mouthLeft,
    .mouthLowerDownLeft, .mouthLowerDownRight,
    .mouthPressLeft, .mouthPressRight, .mouthPucker, .mouthRight,
    .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
    .mouthSmileLeft, .mouthSmileRight,                   // 44, 45
    .mouthStretchLeft, .mouthStretchRight,
    .mouthUpperUpLeft, .mouthUpperUpRight,
    .noseSneerLeft, .noseSneerRight,
]

func arkitBlendShapeArray(from blendShapes: [ARFaceAnchor.BlendShapeLocation: NSNumber]) -> [Float] {
    var out = [Float](repeating: 0, count: kMPBlendShapeOrder.count)
    for (index, key) in kMPBlendShapeOrder.enumerated() {
        if let key { out[index] = blendShapes[key]?.floatValue ?? 0 }
    }
    return out
}
