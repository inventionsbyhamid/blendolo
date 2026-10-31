# Face Landmarker results made up for tests, shaped like MediaPipe's: 478 landmarks (an oval face of the given width
# and centre), blendshape scores and a 4x4 transformation matrix (column-major) for the head's yaw and pitch.
module FaceResults
  POINTS = 478

  module_function

  def result(*faces)
    {
      faceLandmarks: faces.map { |face| landmarks(**face.slice(:width, :centre)) },
      faceBlendshapes: faces.map { |face| { categories: blendshapes(face.fetch(:scores, {})) } },
      facialTransformationMatrixes: faces.map { |face| { data: matrix(face.fetch(:yaw, 0), face.fetch(:pitch, 0)) } }
    }
  end

  def face(width: 0.4, centre: [ 0.5, 0.5 ], yaw: 0, pitch: 0, **scores)
    { width:, centre:, yaw:, pitch:, scores: }
  end

  def landmarks(width:, centre:)
    Array.new(POINTS) do |index|
      angle = 2 * Math::PI * index / POINTS
      { x: (centre[0] + width / 2 * Math.cos(angle)).round(4), y: (centre[1] + width * 0.65 * Math.sin(angle)).round(4) }
    end
  end

  def blendshapes(scores)
    defaults = { eyeBlinkLeft: 0.05, eyeBlinkRight: 0.05, eyeSquintLeft: 0.1, eyeSquintRight: 0.1, jawOpen: 0.02 }
    defaults.merge(scores).map { |name, score| { categoryName: name.to_s, score: } }
  end

  # Rotation about y (yaw) then x (pitch), as MediaPipe's facial transformation matrix (column-major).
  def matrix(yaw, pitch)
    y = yaw * Math::PI / 180
    p = pitch * Math::PI / 180
    rotation = [
      [ Math.cos(y), Math.sin(y) * Math.sin(p), Math.sin(y) * Math.cos(p) ],
      [ 0, Math.cos(p), -Math.sin(p) ],
      [ -Math.sin(y), Math.cos(y) * Math.sin(p), Math.cos(y) * Math.cos(p) ]
    ]
    [ 0, 1, 2 ].flat_map { |column| [ *[ 0, 1, 2 ].map { |row| rotation[row][column].round(6) }, 0 ] } + [ 0, 0, -40, 1 ]
  end
end
