import Foundation

public enum ListeningErrorDescription {
  public static func describe(_ error: Error) -> String {
    let isNSErrorObject = Mirror(reflecting: error).displayStyle == .class
    guard isNSErrorObject || error is CocoaError || error is POSIXError || error is URLError else {
      return error.localizedDescription
    }
    let nsError = error as NSError
    var description = "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    if let path = nsError.userInfo[NSFilePathErrorKey] as? String {
      description += " \(path)"
    } else if let url = nsError.userInfo[NSURLErrorKey] as? URL {
      description += " \(url.path(percentEncoded: false))"
    }

    var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
    for _ in 0..<3 {
      guard let current = underlying else { break }
      description += "\nunderlying: [\(current.domain) \(current.code)] \(current.localizedDescription)"
      underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return description
  }
}
