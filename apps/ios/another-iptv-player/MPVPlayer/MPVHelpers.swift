import CoreGraphics
import Foundation

public enum MPVHelpers {
  /// iOS / minimal libmpv derlemelerinde birçok masaüstü seçeneği yoktur; uygulamayı öldürmemek için yutulur.
  /// `mpv_error` (client.h): OPTION_NOT_FOUND -5, PROPERTY_NOT_FOUND -8, PROPERTY_UNAVAILABLE -10
  private static func isIgnorablePropertyOrOptionError(_ code: CInt) -> Bool {
    code == -5 || code == -8 || code == -10
  }

  /// Mpv hata kodlarını yutar ve loglar. Eskiden `exit(1)` çağırıyordu — artık asla.
  /// Geri dönüş: `true` = başarı; çağıran kritik bir yoldaysa bu bool'a göre branch yapmalı.
  @discardableResult
  public static func checkError(_ status: CInt) -> Bool {
    if status < 0 {
      Log.error("MPVHelpers", "mpv error: \(String(cString: mpv_error_string(status)))")
      return false
    }
    return true
  }

  /// Eksik özellik/option (minimal libmpv) normal kabul edilir; gerçek hata loglanır ama yutulur.
  public static func setPropertyStringIfSupported(
    _ handle: OpaquePointer,
    name: String,
    value: String
  ) {
    name.withCString { nk in
      value.withCString { nv in
        let status = mpv_set_property_string(handle, nk, nv)
        if status < 0 {
          if isIgnorablePropertyOrOptionError(status) {
            Log.info(
              "MPVHelpers",
              "skipping unsupported property '\(name)': \(String(cString: mpv_error_string(status)))"
            )
            return
          }
          checkError(status)
        }
      }
    }
  }

  public static func getVideoOutParams(
    _ handle: OpaquePointer
  ) -> MPVVideoOutParams {
    var node = mpv_node()
    defer {
      mpv_free_node_contents(&node)
    }

    let status = mpv_get_property(handle, "video-out-params", MPV_FORMAT_NODE, &node)
    if status < 0 {
      return MPVVideoOutParams.empty
    }

    if node.format != MPV_FORMAT_NODE_MAP {
      return MPVVideoOutParams.empty
    }
    guard let listPtr = node.u.list else {
      // Mpv invariant'ı: format MAP ise list dolu olmalı. Yine de defansif.
      return MPVVideoOutParams.empty
    }
    let map: mpv_node_list = listPtr.pointee
    if map.num == 0 {
      return MPVVideoOutParams.empty
    }

    return MPVVideoOutParams.fromMPVNodeList(map)
  }

  /// `video-params` düz haritasından tamsayı (veya double) alanları okur.
  /// libmpv `real.dart` görüntü boyutu için **`dw` / `dh`** kullanır; `w`/`h` yedektir.
  public static func getVideoParamsDisplayDimensions(_ handle: OpaquePointer) -> (
    dw: Int64,
    dh: Int64,
    w: Int64,
    h: Int64,
    rotate: Int64
  ) {
    var node = mpv_node()
    defer {
      mpv_free_node_contents(&node)
    }
    let status = mpv_get_property(handle, "video-params", MPV_FORMAT_NODE, &node)
    if status < 0 {
      return (0, 0, 0, 0, 0)
    }
    if node.format != MPV_FORMAT_NODE_MAP {
      return (0, 0, 0, 0, 0)
    }
    guard let listPtr = node.u.list else { return (0, 0, 0, 0, 0) }
    let map: mpv_node_list = listPtr.pointee
    var dw: Int64 = 0
    var dh: Int64 = 0
    var w: Int64 = 0
    var h: Int64 = 0
    var rotate: Int64 = 0
    guard map.num > 0, var kptr = map.keys, var vptr = map.values else {
      return (0, 0, 0, 0, 0)
    }
    for _ in 0 ..< map.num {
      guard let keyCstr = kptr.pointee else {
        kptr = kptr.successor(); vptr = vptr.successor(); continue
      }
      let key = String(cString: keyCstr)
      let value: mpv_node = vptr.pointee
      kptr = kptr.successor()
      vptr = vptr.successor()
      let iv: Int64?
      switch value.format {
      case MPV_FORMAT_INT64:
        iv = value.u.int64
      case MPV_FORMAT_DOUBLE:
        iv = Int64(value.u.double_)
      default:
        iv = nil
      }
      guard let n = iv else { continue }
      switch key {
      case "dw": dw = n
      case "dh": dh = n
      case "w": w = n
      case "h": h = n
      case "rotate": rotate = n
      default: break
      }
    }
    return (dw, dh, w, h, rotate)
  }

  /// Yalnızca **mpv API kuyruğundan** çağrılmalı. Render iş parçacığında `mpv_get_property` yasaktır (kilitlenme).
  public static func computeMpvDerivedDisplaySize(handle: OpaquePointer) -> CGSize {
    let out = getVideoOutParams(handle)
    var dw = out.dw
    var dh = out.dh
    var rot = out.rotate

    if dw <= 0 || dh <= 0 {
      let vp = getVideoParamsDisplayDimensions(handle)
      if vp.dw > 0, vp.dh > 0 {
        dw = vp.dw
        dh = vp.dh
        rot = vp.rotate
      } else if vp.w > 0, vp.h > 0 {
        dw = vp.w
        dh = vp.h
        rot = vp.rotate
      }
    }

    if dw <= 0 || dh <= 0 {
      return .zero
    }

    if rot == 0 || rot == 180 {
      return CGSize(width: Double(dw), height: Double(dh))
    }
    return CGSize(width: Double(dh), height: Double(dw))
  }

  /// Yalnızca **mpv API kuyruğundan** çağrılmalı.
  public static func getDoubleProperty(_ handle: OpaquePointer, name: String) -> Double? {
    var v: Double = 0
    let st = name.withCString { mpv_get_property(handle, $0, MPV_FORMAT_DOUBLE, &v) }
    guard st >= 0 else { return nil }
    return v
  }

  /// Yalnızca **mpv API kuyruğundan** çağrılmalı.
  public static func getFlagProperty(_ handle: OpaquePointer, name: String) -> Bool? {
    var v: CInt = 0
    let st = name.withCString { mpv_get_property(handle, $0, MPV_FORMAT_FLAG, &v) }
    guard st >= 0 else { return nil }
    return v != 0
  }

  /// Yalnızca **mpv API kuyruğundan** çağrılmalı.
  public static func getInt64Property(_ handle: OpaquePointer, name: String) -> Int64? {
    var v: Int64 = 0
    let st = name.withCString { mpv_get_property(handle, $0, MPV_FORMAT_INT64, &v) }
    guard st >= 0 else { return nil }
    return v
  }

  /// Yalnızca **mpv API kuyruğundan** çağrılmalı. Dönen bellek `mpv_free` ile serbest bırakılır.
  public static func getStringProperty(_ handle: OpaquePointer, name: String) -> String? {
    var cstr: UnsafeMutablePointer<CChar>?
    let st = name.withCString { mpv_get_property(handle, $0, MPV_FORMAT_STRING, &cstr) }
    defer {
      if let p = cstr { mpv_free(p) }
    }
    guard st >= 0, let p = cstr else { return nil }
    return String(cString: p)
  }

  /// `mpv_observe_property` başarısız olursa (minimal derleme) yutulur.
  public static func observePropertyIfAvailable(
    _ handle: OpaquePointer,
    replyId: UInt64,
    name: String,
    format: mpv_format
  ) {
    name.withCString { cstr in
      let r = mpv_observe_property(handle, replyId, cstr, format)
      if r < 0 {
        Log.info(
          "MPVHelpers",
          "observe_property skip '\(name)': \(String(cString: mpv_error_string(r)))"
        )
      }
    }
  }
}
