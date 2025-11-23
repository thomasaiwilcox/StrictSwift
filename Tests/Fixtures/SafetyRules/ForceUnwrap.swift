import Foundation

func processData(_ data: Data?) -> String {
    // VIOLATION: Force unwrap
    let string = String(data: data!)!
    return string
}

func safeProcessing(_ data: Data?) -> String? {
    // SAFE: Optional binding
    guard let data = data else { return nil }
    return String(data: data)
}

func dangerousValue(_ value: String?) -> String {
    // VIOLATION: Multiple force unwraps
    let url = URL(string: value!)!
    let components = url.pathComponents.last!
    return components
}

func saferValue(_ value: String?) -> String? {
    // SAFE: Guard let chaining
    guard let value = value,
          let url = URL(string: value),
          let components = url.pathComponents.last else {
        return nil
    }
    return components
}

// VIOLATION: try!
func loadFile(_ path: String) -> String {
    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
    return String(data: data)
}

// SAFE: try-catch
func safeLoadFile(_ path: String) -> String? {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return String(data: data)
    } catch {
        return nil
    }
}