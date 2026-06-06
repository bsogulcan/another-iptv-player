import Foundation

public struct VideoOutputConfiguration {
  public let width: Int64?
  public let height: Int64?
  public let enableHardwareAcceleration: Bool

  public init(
    width: Int64?,
    height: Int64?,
    enableHardwareAcceleration: Bool
  ) {
    self.width = width
    self.height = height
    self.enableHardwareAcceleration = enableHardwareAcceleration
  }
}
